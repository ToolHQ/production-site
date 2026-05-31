export interface CopilotSession {
  authenticated: boolean;
  enabled: boolean;
}

export interface ChatResponse {
  reply: string;
  model: string;
  sources: string[];
  latency_ms: number;
}
