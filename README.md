# InsurancePool (Clarity)

A minimal, compilable registry-style insurance pool contract. It lets a creator register a pool with parameters, toggle whether it’s active, and update parameters later. It stores pool metadata but does not move funds or implement contribution/payout logic.

This README explains storage, public/read-only functions, error codes, deployment, and typical usage.


## Features

- Create a pool with:
  - SIP-010 token principal (stored as a principal; not statically enforced to the trait)
  - Premium rate (in basis points)
  - Minimum contribution
- Toggle pool active flag (creator only)
- Update premium and minimum contribution (creator only)
- Lightweight read-only helpers:
  - Get full pool tuple
  - Check if pool is active
  - Get stored total funds
  - Calculate premiums deterministically


## File layout

- Contract: contracts/InsurancePool.clar
- This doc: contracts/README.md


## Storage schema

Map: pools, keyed by { pool-id: uint }

Value tuple:
- creator: principal
- token: principal
- total-funds: uint
- premium-rate-bp: uint (basis points, 1% = 100, 100% = 10_000)
- min-contribution: uint (> 0)
- active: bool

Notes:
- The contract defines a sip010-ft trait alias but currently stores the token as a plain principal.
- total-funds is a stored number and is not updated by the current code.


## Constants and errors

- MAX_BPS = u10000 (100%)

Error codes (uint):
- ERR-ALREADY-EXISTS = u409
- ERR-NOT-FOUND = u404
- ERR-UNAUTHORIZED = u401
- ERR-INVALID-BPS = u422
- ERR-INVALID-MIN-CONTRIB = u423


## Public functions

1) create-pool(pool-id uint, token principal, premium-rate-bp uint, min-contribution uint) -> (response uint uint)
- Authorization: anyone
- Preconditions:
  - premium-rate-bp ≤ 10_000
  - min-contribution > 0
  - pool-id must be unused
- Effects:
  - Inserts a new pool
  - creator := tx-sender
  - total-funds := 0
  - active := true
- Returns:
  - (ok pool-id) on success
  - (err ERR-INVALID-BPS) | (err ERR-INVALID-MIN-CONTRIB) | (err ERR-ALREADY-EXISTS)

2) set-active(pool-id uint, active bool) -> (response bool uint)
- Authorization: only pool creator
- Preconditions:
  - Pool must exist
  - Caller must equal creator
- Effects:
  - Updates the active flag only
- Returns:
  - (ok active)
  - (err ERR-NOT-FOUND) | (err ERR-UNAUTHORIZED)

3) update-params(pool-id uint, premium-rate-bp uint, min-contribution uint) -> (response bool uint)
- Authorization: only pool creator
- Preconditions:
  - Pool must exist
  - Caller must equal creator
  - premium-rate-bp ≤ 10_000
  - min-contribution > 0
- Effects:
  - Updates premium-rate-bp and min-contribution only
- Returns:
  - (ok true)
  - (err ERR-NOT-FOUND) | (err ERR-UNAUTHORIZED) | (err ERR-INVALID-BPS) | (err ERR-INVALID-MIN-CONTRIB)


## Read-only functions

- get-pool(pool-id uint) -> (optional { ...tuple })
  - Returns some(tuple) if found; none otherwise

- is-active(pool-id uint) -> bool
  - Returns active if found; otherwise false

- get-total-funds(pool-id uint) -> uint
  - Returns total-funds if found; otherwise u0

- calc-premium(amount uint, premium-rate-bp uint) -> uint
  - Computes amount * premium-rate-bp / MAX_BPS
  - Uses integer division (truncates toward zero)


## Quickstart (Clarinet)

Prerequisites:
- Node.js and npm
- Clarinet: npm i -g @hirosystems/clarinet

1) Project setup
- Create or use an existing Clarinet project
- Place InsurancePool.clar under contracts/

2) Check and test compile
- clarinet check

3) Console usage
- clarinet console

Inside the console:

Example principals:
- Let token be a deployed SIP-010 token contract principal (use your actual addresses).

Examples:
- Create a pool:
  - (contract-call? .insurance-pool create-pool u1 'ST123... .token u250 u1000)
  - Returns (ok u1) on success

- Read the pool:
  - (contract-call? .insurance-pool get-pool u1) ; if declared public as read-only via (define-read-only ...), use (contract-call?)? For read-only use (contract-call? .insurance-pool get-pool u1) in Clarinet console context.

- Check active:
  - (contract-call? .insurance-pool is-active u1)
  - => true

- Update params (creator only):
  - (contract-call? .insurance-pool update-params u1 u300 u500)
  - => (ok true)

- Deactivate:
  - (contract-call? .insurance-pool set-active u1 false)
  - => (ok false)

- Calculate premium (read-only utility):
  - (contract-call? .insurance-pool calc-premium u100_000 u250)
  - => u2500

Notes on principals in console:
- Use a proper contract principal like 'ST... .ft-token for token argument.
- tx-sender is the active console wallet; switch using (use-trait or set_tx_sender …) depending on your console helper functions or Clarinet profiles.


## Behavioral notes

- Basis points are capped at 10,000.
- Minimum contribution must be strictly greater than zero.
- Only the original creator (creator field) can update active flag or parameters.
- get-total-funds and is-active return default values if the pool is not found (u0, false).
- Integer math truncates in calc-premium; there is no rounding.


## Security considerations

- Token type is not enforced at the type level:
  - token is stored as principal; the contract does not verify it implements SIP-010 at runtime.
  - If you later add token interactions, enforce the token parameter type as (contract-of sip010-ft) and/or add runtime checks.
- No funds are moved and total-funds is not maintained by this contract.
- No reentrancy concerns in current state, but if you add token callbacks or cross-contract calls, carefully validate responses and order of operations.
- Access control is simple and tied to creator; consider admin patterns if a DAO or multisig should control pools.


## Extending the contract

- Enforce SIP-010 at the type level:
  - Accept token as (contract principal) constrained by (contract-of sip010-ft) in public functions.
- Add contribution and payout flows:
  - Interact with the SIP-010 token to transfer funds; keep total-funds in sync.
- Emit events with print for important state transitions.
- Add pagination/indexing helpers (e.g., store a list of pool-ids or use events for indexing).
- Add admin/owner transfer functionality if creator needs to be rotated.
- Validate that premium-rate-bp and min-contribution updates won’t break downstream flows.


## Testing guide

With Clarinet:
- Unit tests for:
  - Creating pools (valid and invalid)
  - Authorization checks on set-active and update-params
  - Error boundary tests for premium-rate-bp and min-contribution
  - Read-only behavior when pool is missing
  - calc-premium edge cases (0, MAX_BPS, large amounts)

Example test cases to implement:
- create-pool rejects bps > 10_000
- create-pool rejects min-contribution == 0
- second create-pool on same pool-id returns ERR-ALREADY-EXISTS
- Non-creator cannot set-active or update-params
- is-active returns false for unknown pool
- get-total-funds returns u0 for unknown pool
- calc-premium(u100_000, u250) == u2500


## Known limitations

- Pure registry; no token balances are moved.
- total-funds is not updated by any function in this contract.
- Token is not trait-constrained; misuse is possible unless enforced externally.
- No pagination or enumeration of pools; consumer must track ids.


Specify your project’s license here (e.g., MIT).
