import type { LiveOptions, LiveToken } from './live.js';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
import { z } from 'zod';
import { ephemeralSecret, isValidInstallId, issueToken, verifyToken } from './auth.js';
import { type ChatEvent, runChat, summarise } from './brain/chat.js';
import { promptVersion } from './brain/context.js';
import { ChatRequestSchema, formatZodError, HistoryTurnSchema } from './brain/schema.js';
import { type Config, isLlmConfigured, isSearchConfigured, isSttConfigured, isTtsConfigured } from './config.js';
import { notConfigured, ServiceError } from './errors.js';
import type { LlmProvider } from './providers/llm/types.js';
import type { SearchProvider } from './providers/search/types.js';
import type { SttProvider } from './providers/stt/types.js';
import type { TtsProvider } from './providers/tts/types.js';
import type { YoutubeVideo } from './providers/search/gemini.js';
import type { WeatherReport } from './tools/weather.js';

export interface Deps {
  config: Config;
  llm: LlmProvider | null;
  search: SearchProvider | null;
  stt: SttProvider | null;
  tts: TtsProvider | null;
  /** Mints a Gemini Live ephemeral token; null when live mode is not configured. */
  live?: ((o: LiveOptions) => Promise<LiveToken>) | null;
  weather: (city: string) => Promise<WeatherReport>;
  /** Finds embeddable YouTube videos for in-app playback; null when not configured. */
  youtube?: ((query: string) => Promise<YoutubeVideo[]>) | null;
  promptTemplate: string;
  logger?: boolean;
}

declare module 'fastify' {
  interface FastifyRequest {
    installId?: string;
  }
}

const VERSION = '0.1.0';

function sendError(reply: FastifyReply, err: unknown): FastifyReply {
  if (err instanceof ServiceError) return reply.code(err.status).send({ error: { code: err.code, message: err.message } });
  reply.log.error({ err: err instanceof Error ? err.name : 'unknown' }, 'unhandled error');
  return reply.code(500).send({ error: { code: 'server_error', message: 'Internal error' } });
}

/**
 * Synchronous on purpose: Vercel's Fastify launcher needs `listen()` to be
 * called without a top-level `await` before it (verified with temporary
 * deployments). Plugins and routes are registered inside one non-encapsulated
 * plugin that Fastify loads before `listen()`/`inject()`/`ready()` resolve.
 */
export function buildServer(deps: Deps): FastifyInstance {
  const { config } = deps;
  const secret = config.authSecret || ephemeralSecret();
  const app = Fastify({
    bodyLimit: config.jsonBodyLimitBytes,
    trustProxy: true,
    logger: deps.logger === false ? false : {
      level: process.env.LOG_LEVEL ?? 'info',
      redact: ['req.headers.authorization', 'req.headers["x-api-key"]'],
      // Only method + path are logged; never bodies or query strings (they can contain user text).
      serializers: {
        req: (req: { method?: string; url?: string }) => ({ method: req.method, path: (req.url ?? '').split('?')[0] }),
        res: (res: { statusCode?: number }) => ({ statusCode: res.statusCode }),
      },
    },
  });

  const routes = async (app: FastifyInstance): Promise<void> => {
    if (!config.authSecret) app.log.warn('AUTH_SECRET not set: using an ephemeral secret, tokens reset on restart');

    await app.register(cors, {
      // Native apps do not need CORS. Browsers are only allowed from explicit origins.
      origin: config.corsOrigins.length ? config.corsOrigins : false,
      methods: ['GET', 'POST'],
    });

    await app.register(rateLimit, {
      max: config.rateLimitPerMinute,
      timeWindow: '1 minute',
      keyGenerator: (req) => {
        const h = req.headers.authorization;
        const id = h?.startsWith('Bearer ') ? verifyToken(secret, h.slice(7)) : null;
        return id ?? req.ip;
      },
      errorResponseBuilder: (_req, ctx) => ({ statusCode: 429, error: { code: 'rate_limited', message: `Too many requests, retry in ${Math.ceil(ctx.ttl / 1000)}s` } }),
    });

    // Raw audio bodies for STT.
    for (const ct of ['audio/wav', 'audio/x-wav', 'audio/ogg', 'audio/webm', 'audio/mp4', 'audio/m4a', 'audio/mpeg', 'application/octet-stream']) {
      app.addContentTypeParser(ct, { parseAs: 'buffer', bodyLimit: config.audioBodyLimitBytes }, (_req, body, done) => done(null, body));
    }

    const requireAuth = async (req: FastifyRequest, reply: FastifyReply) => {
      const h = req.headers.authorization;
      const id = h?.startsWith('Bearer ') ? verifyToken(secret, h.slice(7)) : null;
      if (!id) return reply.code(401).send({ error: { code: 'unauthorized', message: 'Missing or invalid install token' } });
      req.installId = id;
    };

    app.get('/v1/health', async () => ({
      ok: true,
      version: VERSION,
      prompt_version: promptVersion(deps.promptTemplate),
      services: {
        llm: { configured: isLlmConfigured(config) && !!deps.llm, provider: config.llm.provider },
        search: { configured: isSearchConfigured(config) && !!deps.search, provider: config.search.provider },
        youtube: { configured: !!deps.youtube, provider: deps.youtube ? 'youtube-embed' : 'none' },
        weather: { configured: true, provider: 'open-meteo' },
        stt: { configured: isSttConfigured(config) && !!deps.stt, provider: config.stt.provider },
        tts: { configured: isTtsConfigured(config) && !!deps.tts, provider: config.tts.provider },
        live: { configured: !!deps.live, provider: deps.live ? 'gemini-live' : 'none' },
      },
      time: new Date().toISOString(),
    }));

    app.post('/v1/auth/anonymous', { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (req, reply) => {
      const parsed = z.object({ install_id: z.string() }).safeParse(req.body);
      if (!parsed.success || !isValidInstallId(parsed.data.install_id)) {
        return reply.code(400).send({ error: { code: 'bad_request', message: 'install_id must be a UUID' } });
      }
      return { token: issueToken(secret, parsed.data.install_id), expires_in: 60 * 60 * 24 * 30 };
    });

    app.post('/v1/chat', { preHandler: requireAuth, bodyLimit: config.chatBodyLimitBytes }, async (req, reply) => {
      const parsed = ChatRequestSchema.safeParse(req.body);
      if (!parsed.success) return reply.code(400).send({ error: { code: 'bad_request', message: formatZodError(parsed.error) } });
      if (!deps.llm || !isLlmConfigured(config)) return sendError(reply, notConfigured('AI'));

      reply.hijack();
      const raw = reply.raw;
      raw.writeHead(200, { 'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-cache, no-transform', connection: 'keep-alive', 'x-accel-buffering': 'no' });
      const send = (event: string, data: unknown) => raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      let closed = false;
      req.raw.on('close', () => {
        closed = true;
      });
      try {
        const gen = runChat(parsed.data, {
          llm: deps.llm,
          search: isSearchConfigured(config) ? deps.search : null,
          weather: deps.weather,
          promptTemplate: deps.promptTemplate,
          tokenBudget: config.contextTokenBudget,
          maxOutputTokens: config.llm.maxOutputTokens,
        });
        for await (const ev of gen as AsyncGenerator<ChatEvent>) {
          if (closed) break;
          if (ev.type === 'status') send('status', { phase: ev.phase });
          else {
            // Transport-level streaming of the validated text, then the full structured reply.
            const words = ev.reply.display_text.split(/(\s+)/);
            for (let i = 0; i < words.length; i += 6) send('delta', { text: words.slice(i, i + 6).join('') });
            send('final', ev.reply);
          }
        }
      } catch (err) {
        const e = err instanceof ServiceError ? err : new ServiceError('upstream_error', 'Unexpected error', 500);
        if (!(err instanceof ServiceError)) req.log.error({ err: err instanceof Error ? err.name : 'unknown' }, 'chat failed');
        send('error', { code: e.code, message: e.message });
      } finally {
        raw.end();
      }
    });

    app.post('/v1/summarize', { preHandler: requireAuth }, async (req, reply) => {
      const parsed = z.object({ summary: z.string().max(3000).optional(), turns: z.array(HistoryTurnSchema).min(1).max(40) }).safeParse(req.body);
      if (!parsed.success) return reply.code(400).send({ error: { code: 'bad_request', message: formatZodError(parsed.error) } });
      if (!deps.llm || !isLlmConfigured(config)) return sendError(reply, notConfigured('AI'));
      try {
        return { summary: await summarise(deps.llm, parsed.data.summary, parsed.data.turns, config.llm.maxOutputTokens) };
      } catch (err) {
        return sendError(reply, err);
      }
    });

    app.get('/v1/weather', { preHandler: requireAuth }, async (req, reply) => {
      const parsed = z.object({ city: z.string().min(1).max(80) }).safeParse(req.query);
      if (!parsed.success) return reply.code(400).send({ error: { code: 'bad_request', message: 'city is required' } });
      try {
        return await deps.weather(parsed.data.city);
      } catch (err) {
        return sendError(reply, err);
      }
    });

    app.get('/v1/music/youtube', { preHandler: requireAuth }, async (req, reply) => {
      if (!deps.youtube) return sendError(reply, notConfigured('YouTube search'));
      const parsed = z.object({ q: z.string().trim().min(1).max(120) }).safeParse(req.query);
      if (!parsed.success) return reply.code(400).send({ error: { code: 'bad_request', message: 'q is required' } });
      try {
        return { videos: await deps.youtube(parsed.data.q) };
      } catch (err) {
        return sendError(reply, err);
      }
    });

    app.post('/v1/stt', { preHandler: requireAuth, bodyLimit: config.audioBodyLimitBytes }, async (req, reply) => {
      if (!deps.stt || !isSttConfigured(config)) return sendError(reply, notConfigured('Cloud speech recognition'));
      const lang = z.string().regex(/^[a-z]{2}(-[A-Z]{2})?$/).safeParse((req.query as Record<string, unknown>)?.lang ?? 'ar-MA');
      if (!lang.success) return reply.code(400).send({ error: { code: 'bad_request', message: 'lang must look like ar-MA' } });
      const body = req.body;
      if (!Buffer.isBuffer(body) || body.length < 44) return reply.code(400).send({ error: { code: 'bad_request', message: 'audio body required' } });
      try {
        // Audio is processed in memory and discarded; nothing is written to disk or logs.
        return await deps.stt.transcribe(body, String(req.headers['content-type'] ?? 'audio/wav').split(';')[0]!, lang.data);
      } catch (err) {
        return sendError(reply, err);
      }
    });

    app.post('/v1/tts', { preHandler: requireAuth }, async (req, reply) => {
      if (!deps.tts || !isTtsConfigured(config)) return sendError(reply, notConfigured('Cloud text-to-speech'));
      const parsed = z
        .object({
          text: z.string().trim().min(1).max(1500),
          language: z.string().regex(/^[a-z]{2}-[A-Z]{2}$/).default('ar-MA'),
          // Azure neural voice id or a Gemini prebuilt voice name.
          voice: z.string().regex(/^([a-z]{2}-[A-Z]{2}-[A-Za-z]+Neural|[A-Z][a-z]{2,15})$/).optional(),
          gender: z.enum(['male', 'female']).optional(),
          rate: z.number().min(0.5).max(2).optional(),
          pitch: z.number().min(0.5).max(2).optional(),
        })
        .safeParse(req.body);
      if (!parsed.success) return reply.code(400).send({ error: { code: 'bad_request', message: formatZodError(parsed.error) } });
      try {
        const out = await deps.tts.synthesize(parsed.data);
        return reply.header('content-type', out.contentType).header('cache-control', 'no-store').send(out.audio);
      } catch (err) {
        return sendError(reply, err);
      }
    });

    app.post('/v1/live/token', { preHandler: requireAuth, config: { rateLimit: { max: 6, timeWindow: '1 minute' } } }, async (req, reply) => {
      if (!deps.live) return sendError(reply, notConfigured('Live camera'));
      const parsed = z
        .object({
          robot_name: z.string().max(30).optional(),
          user_name: z.string().max(40).optional(),
          gender: z.enum(['male', 'female']).default('male'),
          reply_language: z.enum(['darija', 'ar', 'fr', 'en']).default('darija'),
        })
        .safeParse(req.body ?? {});
      if (!parsed.success) return reply.code(400).send({ error: { code: 'bad_request', message: formatZodError(parsed.error) } });
      try {
        const d = parsed.data;
        const t = await deps.live({ robotName: d.robot_name, userName: d.user_name, gender: d.gender, replyLanguage: d.reply_language });
        return reply.header('cache-control', 'no-store').send(t);
      } catch (err) {
        return sendError(reply, err);
      }
    });
  };
  // Same effect as fastify-plugin: register in the root context (no encapsulation).
  Object.assign(routes, { [Symbol.for('skip-override')]: true });
  void app.register(routes);

  return app;
}
