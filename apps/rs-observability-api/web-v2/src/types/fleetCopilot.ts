export interface CopilotSession {
  authenticated: boolean;
  enabled: boolean;
}

export interface CopilotStatus extends CopilotSession {
  gateway_reachable: boolean;
  ollama_model: string;
  inference_mode: string;
  structured_models: string[];
  rate_limit_max: number;
  rate_limit_remaining: number;
  thread_context: boolean;
}

export interface ChatResponse {
  reply: string;
  model: string;
  sources: string[];
  latency_ms: number;
}
