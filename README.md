# CharityVault 🔒

Trustless crowdfunding on Base. Kickstarter-style, no intermediaries.

- Funds locked on-chain until goal is reached
- Missed deadline → everyone reclaims their ETH automatically
- Creator can cancel early (contributors refund)
- One HTML file frontend, no build step

---

## Contract Logic

| Scenario | Result |
|---|---|
| Deadline passed + goal reached | Creator calls `claimFunds()` |
| Deadline passed + goal NOT reached | Contributors call `refund()` |
| Creator cancelled before deadline | Contributors call `refund()` |

**Status codes returned by `getStatus(id)`:**
```
0 = Active
1 = Succeeded (awaiting claim)
2 = Failed (refunds open)
3 = Claimed
4 = Cancelled
```

---

## Deploy

```bash
# 1. Install
npm install

# 2. Configure
cp .env.example .env
# fill PRIVATE_KEY and BASESCAN_API_KEY

# 3. Deploy to Base Sepolia (testnet)
npx hardhat run scripts/deploy.js --network base-sepolia

# 4. Deploy to Base Mainnet
npx hardhat run scripts/deploy.js --network base

# 5. After deploy — update CONTRACT_ADDRESS in frontend/index.html
```

---

## Frontend

Open `frontend/index.html` in any browser. No build step, no dependencies except ethers.js from CDN.

Update `CONTRACT_ADDRESS` at the top of the `<script>` block after deploying.

**Features:**
- Connect MetaMask / Coinbase Wallet
- Browse all campaigns with category filter
- Create campaign (title, description, image, goal, duration)
- Contribute ETH
- Withdraw funds (creator, after success)
- Get refund (any contributor, after failure/cancel)
- Cancel campaign (creator only, while active)
- Live progress bar, backer count, countdown

---

## Use Cases

- 🏥 Medical treatment crowdfunding
- 🎪 Event funding (concerts, meetups)
- 💻 Open source project grants
- 🖼 NFT project presales
- 📦 Anything else

---

## Security Notes

- No admin key, no upgradeability — fully immutable
- Reentrancy protected: state updated before external calls
- All ETH transfers use low-level `.call{}` with revert on failure
- Creator cannot withdraw unless goal is met and deadline passed
- Contributors cannot be locked out — refund always available post-failure
