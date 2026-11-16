/** Provider-neutral conversation model used by the brain. */
export type Block =
  | { type: 'text'; text: string }
  | { type: 'tool_use'; id: string; name: string; input: Record<string, unknown> }
  | { type: 'tool_result'; tool_use_id: string; content: string; is_error?: boolean };

export interface LlmMessage {
  role: 'user' | 'assistant';
  content: Block[];
}

export interface ToolDef {
  name: string;
  description: string;
  /** JSON Schema object */
  input_schema: Record<string, unknown>;
}

export interface LlmRequest {
  system: string;
  messages: LlmMessage[];
  tools: ToolDef[];
  maxTokens: number;
}

export interface LlmResponse {
  content: Block[];
  stopReason: 'end' | 'tool_use' | 'max_tokens' | 'other';
}

export interface LlmProvider {
  readonly name: string;
  complete(req: LlmRequest): Promise<LlmResponse>;
}
