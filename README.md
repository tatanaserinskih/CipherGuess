# CipherGuess — a private guessing game on Zama FHEVM

A tiny demo of a “guess the number” game built on Zama’s Fully Homomorphic EVM (FHEVM).
The secret number lives **encrypted** on‑chain (`euint16`). The player submits an **encrypted** guess; the contract compares them privately and emits a handle to an encrypted boolean (`ebool`) that can be decrypted via the Relayer SDK.

> **TL;DR**
>
> * **Contract:** Solidity using `@fhevm/solidity` + `SepoliaConfig`
> * **Frontend:** single `index.html` with Ethers (UMD) + Zama Relayer SDK (CDN)
> * **Decryption:** try **private** (`userDecrypt`) first; if it fails, fall back to **public** (`publicDecrypt`)

---

## Architecture

```
Wallet (EIP-712)
     │
     ▼
Relayer SDK (browser) ──► Zama Relayer (testnet)
     │                        │
     │ encrypt input          │ inputProof / attestation
     └──────────────┬─────────┘
                    ▼
             CipherGuess.sol  (FHEVM on Sepolia)
                    │
            FHE.eq(secret, guess)   // all encrypted
                    │
                    ▼
        handle(ebool) → Played event
                    │
         ┌──────────┴───────────┐
         ▼                      ▼
  userDecrypt (private)   publicDecrypt (fallback)
```

---

## Stack

* **Solidity (0.8.25)** + Zama FHEVM:

  * `@fhevm/solidity/lib/FHE.sol` (types `euint16`, `ebool`; API `FHE.*`)
  * `@fhevm/solidity/config/ZamaConfig.sol` (`SepoliaConfig`)
* **Frontend**:

  * Ethers v6 (UMD via CDN)
  * Zama Relayer SDK JS `0.2.0` (CDN)
  * Plain static HTML/JS (no bundler)

---

## Repository layout

```
.
├─ contracts/
│  └─ CipherGuess.sol         # smart contract
├─ web/
│  └─ index.html              # single‑file frontend
└─ README.md
```

---

## Smart contract

Key points:

* The secret is stored as `euint16 _secret`.
* Reseed (`reseed`) accepts an **encrypted** value via `FHE.fromExternal(externalEuint16, proof)`.
* The player submits an **encrypted** guess; the contract computes `FHE.eq` privately.
* ACL:

  * `FHE.allowTransient(win, msg.sender)` — one‑shot private decryption right for the current player.
  * `FHE.makePubliclyDecryptable(win)` — optional **public fallback** (handy for demos).
* Helper `reseedPlain` is for diagnostics only — **remove for production**.

> The contract does **not** do on‑chain range validation for encrypted values (to avoid forcing public decryption). The range is enforced on the frontend.

---

## Frontend

Single `index.html` that:

* Loads Ethers UMD and Relayer SDK from CDN.
* Initializes the SDK with `initSDK()` and `createInstance(SepoliaConfig)`.
* Creates encrypted input with `createEncryptedInput(...).add16(value).encrypt()` → returns `handle` and `inputProof`.
* Calls `play(handle, proof)` and reads the `resultHandle` from the `Played` event.
* Decrypts the result:

  * tries **private** `userDecrypt(...)` first (EIP‑712 signature; requires KMS/ACL to permit the caller),
  * if it fails (e.g., key not provisioned), uses **public** `publicDecrypt(...)` as a fallback.

The page contains extensive `console.log` statements for encryption, transactions, event parsing, and decryption.

---

## Deploying the contract

Use any Ethereum toolchain (Hardhat or Foundry). Example with **Foundry**:

```bash
# 1) init project
forge init cipherguess && cd cipherguess
forge install zama-ai/fhevm-solidity

# 2) put contracts/CipherGuess.sol into your project

# 3) build
forge build

# 4) deploy (example to Sepolia)
forge create --rpc-url $SEPOLIA_RPC \
  --private-key $PK \
  contracts/CipherGuess.sol:CipherGuess \
  --constructor-args 100
```

Save the deployed address for the frontend.

---

## Running the frontend locally

`web/index.html` is a static file. Serve it with any static server, e.g.:

```bash
# Python
cd web
python3 -m http.server 8080

# or Node serve
npx serve -p 8080 web
```

Open `http://localhost:8080` and connect MetaMask to **Sepolia**.

---

## Configuration

Edit this block in `web/index.html`:

```js
window.CONFIG = {
  NETWORK_NAME: "Sepolia",
  CHAIN_ID_HEX: "0xaa36a7",              // 11155111
  CONTRACT_ADDRESS: "0x...your_deployed_address..."
};
```

The Relayer SDK is loaded from `https://cdn.zama.ai/relayer-sdk-js/0.2.0/relayer-sdk-js.js` and uses `SepoliaConfig` with the test relayer and gateway URLs.

---

## How to play

1. Connect your wallet.
2. (Optional, owner only) Enter a seed and press **Reseed (encrypted)**.
3. Enter your guess within the range and press **Play**.
4. Wait for the tx to confirm and the result to decrypt:

   * **You WIN 🎉** — the guess equals the secret,
   * **Nope, try again.** — the guess is different.

---

## Privacy model & ACL

* The secret and the guess are **always encrypted** on‑chain.
* The equality check is performed by the contract over ciphertexts: `FHE.eq`.
* The result is an `ebool` turned into an opaque **handle** (not a plaintext value).
* Decryption rights:

  * **Private:** `FHE.allowTransient(win, msg.sender)` → `userDecrypt` for the caller.
  * **Public fallback:** `FHE.makePubliclyDecryptable(win)` → `publicDecrypt` for anyone.

> For strict privacy, **remove** `FHE.makePubliclyDecryptable(win)` and only keep `userDecrypt` on the frontend. Ensure the caller’s KMS key is correctly provisioned in the network.

---

## Troubleshooting

### “Invalid public or private key”

* The account’s KMS key is not provisioned or mismatched for the network.

  * Ensure you’ve run `createEncryptedInput(...).encrypt()` at least once with this address.
  * Retry `userDecrypt` from the **same** address that called `play()`.
  * Use the public fallback `publicDecrypt` for demos.

### “Contract address is not a valid address” (during encryption)

* Some SDK builds error on the object form `createEncryptedInput({ ... })`. The frontend already falls back to the positional API `createEncryptedInput(contractAddress, userAddress)`.

### “\_.map is not a function” (during publicDecrypt)

* That SDK build expects byte arrays. The frontend converts handles to `Uint8Array(32)` before decrypting.

### “Played, but result handle not found in logs.”

* Check the ABI of `Played` on the frontend and the contract address.
* Verify the tx really targeted your contract (`receipt.to`).

---

## Production notes

* Remove/disable `reseedPlain` — it reveals the secret value.
* For strictly private UX, **do not** call `makePubliclyDecryptable` and remove `publicDecrypt` from the UI.
* Never branch (`require`) on encrypted `ebool` — that would leak information.
* Validate user input **on the frontend**; on‑chain range checks for encrypted values require extra logic and/or public decryption.
* Pin SDK & contract versions; mismatches can break decryption.

---

## License

MIT — for demonstration purposes only. Use at your own risk.

---

## Acknowledgments

Thanks to the Zama team for FHEVM and the Relayer SDK. See the official docs at **docs.zama.ai** (Protocol → Relayer SDK Guides).
