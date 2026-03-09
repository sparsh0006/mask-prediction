# Private Prediction Market — Chainlink CRE

A privacy-preserving prediction market using commit-reveal scheme + Chainlink CRE for AI-powered settlement.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Node.js | v20+ | https://nodejs.org |
| Bun | v1.3+ | `curl -fsSL https://bun.sh/install \| bash` |
| CRE CLI | latest | https://docs.chain.link/cre/getting-started/cli-installation |
| Foundry | latest | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |

## Setup

### 1. Install dependencies
```bash
# Install Foundry libs
cd contracts && forge install foundry-rs/forge-std --no-commit && cd ..

# Install workflow dependencies
cd workflow && bun install && cd ..
```

### 2. Configure environment
```bash
cp .env.example .env
# Edit .env — add your private key and Gemini API key
```

### 3. Login to CRE
```bash
cre login
```

## Deploy to Sepolia

### 4. Deploy the smart contract
```bash
source .env
cd contracts
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $CRE_ETH_PRIVATE_KEY \
  --broadcast
```

Copy the deployed address and update `workflow/config.staging.json`:
```json
{ "evms": [{ "marketAddress": "0xYOUR_DEPLOYED_ADDRESS", ... }] }
```

### 5. Simulate the HTTP trigger (create a market)
```bash
cre workflow simulate workflow/ --broadcast
# Select: 1 (HTTP trigger)
# Enter payload:
# {"question":"Will ETH be above $5000 by June 1 2025?","durationHours":1,"participants":["0xYOUR_ADDRESS"]}
```

### 6. Commit a hidden bet

Generate a commitment hash client-side:
```bash
cast keccak $(cast abi-encode "f(uint8,bytes32,address)" 0 0xDEADBEEF0000000000000000000000000000000000000000000000000000dead 0xYOUR_ADDRESS)
```

Then commit (replace values):
```bash
cast send $MARKET_ADDRESS \
  "commitBet(uint256,bytes32)" 0 0xYOUR_HASH \
  --value 0.01ether \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $CRE_ETH_PRIVATE_KEY
```

### 7. Request settlement (after deadline)
```bash
cast send $MARKET_ADDRESS \
  "requestSettlement(uint256)" 0 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $CRE_ETH_PRIVATE_KEY
```

Save the transaction hash!

### 8. Simulate the Log trigger (AI settlement)
```bash
cre workflow simulate workflow/ --broadcast
# Select: 2 (Log trigger)
# Enter the tx hash from step 7 and event index 0
```

### 9. Reveal your bet (after settlement)
```bash
cast send $MARKET_ADDRESS \
  "revealBet(uint256,uint8,bytes32)" 0 0 0xDEADBEEF... \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $CRE_ETH_PRIVATE_KEY
```

### 10. Finalize reveal phase (admin, after 24h)
```bash
cast send $MARKET_ADDRESS \
  "finalizeRevealPhase(uint256)" 0 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $CRE_ETH_PRIVATE_KEY
```

### 11. Claim winnings
```bash
cast send $MARKET_ADDRESS \
  "claim(uint256)" 0 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $CRE_ETH_PRIVATE_KEY
```

---

## Deploy to Tenderly Virtual TestNet (later)

### 1. Create a Virtual TestNet in Tenderly dashboard
- Go to https://dashboard.tenderly.co → Virtual TestNets → New
- Fork Sepolia, note your Virtual TestNet RPC URL

### 2. Update .env
```bash
TENDERLY_RPC_URL=https://virtual.sepolia.rpc.tenderly.co/YOUR_VNET_ID
```

### 3. Deploy to Tenderly
```bash
source .env
cd contracts
forge script script/Deploy.s.sol \
  --rpc-url $TENDERLY_RPC_URL \
  --private-key $CRE_ETH_PRIVATE_KEY \
  --broadcast
```

### 4. Update config.staging.json with Tenderly contract address

Update `workflow/config.staging.json`:
```json
{
  "evms": [{
    "id": "evm:tenderly-sepolia",
    "chainId": 11155111,
    "marketAddress": "0xTENDERLY_DEPLOYED_ADDRESS",
    "rpc": "https://virtual.sepolia.rpc.tenderly.co/YOUR_VNET_ID"
  }]
}
```

### 5. Simulate and test — same steps 5–11 above, just use $TENDERLY_RPC_URL

Tenderly gives you:
- Unlimited test ETH via faucet
- Real-time transaction explorer
- Time travel (advance block.timestamp past deadlines instantly)
- Gas profiler

To advance time past deadline on Tenderly:
```bash
# Advance time by 2 hours (in seconds)
curl -X POST $TENDERLY_RPC_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"evm_increaseTime","params":[7200],"id":1}'
```

---

## Chainlink Files (for README requirement)

- `workflow/src/workflow.ts` — CRE workflow (HTTP + Log triggers, EVM read/write)
- `workflow/src/gemini.ts` — Gemini AI integration via CRE HTTP capability
- `workflow/config.staging.json` — CRE network configuration
- `project.yaml` — CRE project manifest
- `secrets.yaml` — CRE secrets mapping# ppm
# mask-prediction
