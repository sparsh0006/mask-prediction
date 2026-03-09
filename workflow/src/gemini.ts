// ─────────────────────────────────────────────────────────────────────────────
// Gemini AI Settlement Helper — CRE TypeScript SDK v1.1.x
//
// This module exports `buildGeminiRequest` which is passed to
// HTTPClient.sendRequest(runtime, buildGeminiRequest, consensus)(config)
// in workflow.ts.
//
// The function signature (sendRequester, config) matches the SDK's required
// fn type: (sendRequester: HTTPSendRequester, config: C) => R
//
// Privacy note: swap HTTPClient → ConfidentialHTTPClient in workflow.ts
// when the SDK exits experimental to route through a TEE enclave.
// This file requires no changes for that upgrade.
// ─────────────────────────────────────────────────────────────────────────────

import { ok, text, type HTTPSendRequester } from "@chainlink/cre-sdk";

const GEMINI_URL =
"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent";

// ─────────────────────────────────────────────────────────────────────────────
// Public types
// ─────────────────────────────────────────────────────────────────────────────

export type GeminiConfig = {
  apiKey:   string;   // from runtime.getSecret({ id: "GEMINI_API_KEY" }).result().value
  question: string;
};

export type GeminiSettlementResult = {
  outcome:    "Yes" | "No";
  confidence: number;    // 0–100
  reasoning:  string;
  sources:    string[];
};

// ─────────────────────────────────────────────────────────────────────────────
// buildGeminiRequest
//
//  Called by HTTPClient.sendRequest(runtime, fn, consensus)(config).result()
//  Each DON node executes this independently; consensus then validates agreement.
//
//  Parameters injected by the SDK:
//    sendRequester — exposes .sendRequest({ url, method, headers, body }).result()
//    config        — GeminiConfig passed at the call site in workflow.ts
// ─────────────────────────────────────────────────────────────────────────────

export function buildGeminiRequest(
  sendRequester: HTTPSendRequester,
  config: GeminiConfig
): GeminiSettlementResult {
  const prompt = buildPrompt(config.question);

  const bodyString = JSON.stringify({
    contents: [{ parts: [{ text: prompt }] }],
    tools: [{ googleSearch: {} }],        // grounded web search for accuracy
    generationConfig: {
      temperature:     0.1,               // low temp → deterministic output
      maxOutputTokens: 512,
    },
  });

  // ── POST to Gemini ────────────────────────────────────────────────────────
 const response = sendRequester
  .sendRequest({
    url: `${GEMINI_URL}?key=${config.apiKey}`,
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: Buffer.from(bodyString).toString("base64"),
  })
  .result();

  // ── HTTP error check ──────────────────────────────────────────────────────
  if (!ok(response)) {
    return safeDefault(`Gemini HTTP ${response.statusCode}`);
  }

  // ── Extract text from Gemini response JSON ────────────────────────────────
  const rawText = extractCandidateText(text(response));
  return parseGeminiJSON(rawText);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function buildPrompt(question: string): string {
  return `You are a prediction market resolver. Determine the factual outcome of:

Question: "${question}"

Rules:
1. Use knowledge and Google Search grounding to verify the outcome.
2. Return ONLY valid JSON — no extra text, no markdown fences:
{
  "outcome": "Yes" | "No",
  "confidence": <integer 0-100>,
  "reasoning": "<1-2 sentence explanation with sources>",
  "sources": ["<url or citation>"]
}
3. If confidence is below 60%, set outcome to "No" as a safe default.`;
}

function extractCandidateText(responseBody: string): string {
  try {
    const data = JSON.parse(responseBody) as {
      candidates?: Array<{
        content?: { parts?: Array<{ text?: string }> };
      }>;
    };
    return data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  } catch {
    return "";
  }
}

function parseGeminiJSON(rawText: string): GeminiSettlementResult {
  // Gemini sometimes wraps output in markdown code fences — strip them
  const cleaned = rawText
    .replace(/```json\s*/g, "")
    .replace(/```\s*/g, "")
    .trim();

  try {
    const parsed = JSON.parse(cleaned) as GeminiSettlementResult;

    if (!["Yes", "No"].includes(parsed.outcome)) {
      throw new Error(`Unexpected outcome value: "${parsed.outcome}"`);
    }
    if (typeof parsed.confidence !== "number") {
      throw new Error("Missing or non-numeric confidence field");
    }

    return parsed;
  } catch (e) {
    return safeDefault(`JSON parse failed: ${rawText.slice(0, 80)}`);
  }
}

function safeDefault(reason: string): GeminiSettlementResult {
  return {
    outcome:    "No",
    confidence: 0,
    reasoning:  reason,
    sources:    [],
  };
}