// Shared types used across workflow and gemini modules

export interface MarketConfig {
  chainId: number;
  marketAddress: string;
  rpc: string;
}

export interface EvmConfig {
  id: string;
  chainId: number;
  marketAddress: string;
  rpc: string;
}

export interface WorkflowConfig {
  evms: EvmConfig[];
}

// The question payload sent via HTTP trigger to create a market
export interface CreateMarketPayload {
  question: string;
  durationHours: number;       // how long the market stays open
  participants: string[];      // allowlisted ETH addresses
}

// Gemini's structured response for market resolution
export interface GeminiSettlementResult {
  outcome: "Yes" | "No";
  confidence: number;          // 0-100
  reasoning: string;
  sources: string[];
}

// ABI-encoded report sent to onReport() on contract
// Encoded as: abi.encode(uint256 marketId, uint8 outcome)
export interface SettlementReport {
  marketId: bigint;
  outcome: 0 | 1;              // 0 = Yes, 1 = No
}