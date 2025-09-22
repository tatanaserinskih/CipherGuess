// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/* Zama FHEVM */
import { FHE, euint16, ebool, externalEuint16 } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

/**
 * CipherGuess — private "guess the number" on FHEVM.
 * - Encrypted on-chain secret: euint16 _secret (owner reseeds via fromExternal)
 * - Player submits encrypted guess (euint16) → equality (ebool) is returned as handle
 *
 * Notes:
 * - We DO NOT branch on ebool (no `require` with encrypted conditions).
 * - Range [0..N] валидируется на фронте.
 */
contract CipherGuess is SepoliaConfig {
    /* ─── Ownership ─── */
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }

    /* ─── Game config ─── */
    uint16 public immutable N;      // inclusive upper bound for secret & guesses
    euint16 internal _secret;       // encrypted secret

    /* ─── Events ─── */
    event Seeded(address indexed by);
    event Played(address indexed player, bytes32 resultHandle);

    constructor(uint16 _N) {
        owner = msg.sender;
        N = _N;

        // initialize secret with zero (encrypted literal)
        _secret = FHE.asEuint16(0);

        // ACL for stored ciphertext
        FHE.allowThis(_secret);      // contract can operate on it
        FHE.allow(_secret, owner);   // (optional) owner can decrypt if needed in future flows
    }

    /* ─────────────────────────────
       Owner: reseed secret (encrypted)
       encSecret: external handle of euint16
       proof:     inputProof/attestation from Relayer SDK
       ───────────────────────────── */
    function reseed(externalEuint16 encSecret, bytes calldata proof) external onlyOwner {
        euint16 newSecret = FHE.fromExternal(encSecret, proof);
        _secret = newSecret;

        // Re-allow for future ops
        FHE.allowThis(_secret);
        FHE.allow(_secret, owner);

        emit Seeded(msg.sender);
    }

    /* ─────────────────────────────
       Player: submit encrypted guess
       Returns: handle of ebool (win?)
       ───────────────────────────── */
    function play(externalEuint16 encGuess, bytes calldata proof) external returns (bytes32) {
        euint16 guess = FHE.fromExternal(encGuess, proof);
        ebool win = FHE.eq(guess, _secret);   // equality on encrypted values

        // приватная дешифрация игроку + публичный фолбэк
        FHE.allowTransient(win, msg.sender);
        FHE.makePubliclyDecryptable(win);

        bytes32 h = FHE.toBytes32(win);
        emit Played(msg.sender, h);
        return h;
    }

    /* ─────────────────────────────
       Diagnostics (TEMP! remove in prod)
       ───────────────────────────── */
    function reseedPlain(uint16 v) external onlyOwner {
        require(v <= N, "v>N");
        _secret = FHE.asEuint16(v);      // НЕ для продакшена (контракт узнаёт секрет)
        FHE.allowThis(_secret);
        FHE.allow(_secret, owner);
        emit Seeded(msg.sender);
    }

    /* Опционально: версия для фронта */
    function version() external pure returns (string memory) {
        return "CipherGuess/1.2.1";
    }
}
