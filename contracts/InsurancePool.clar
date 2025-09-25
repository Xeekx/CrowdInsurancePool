;; InsurancePool.clar
;; Minimal, compilable skeleton with corrected storage schema and small helpers.
;; This version fixes tuple typing, uses a trait-typed token principal, and adds light validation and admin ops.

;; --- SIP-010 FT trait alias (minimal) ---
(define-trait sip010-ft (
    (transfer
        (uint principal principal (optional (buff 34)))
        (response bool uint)
    )
    (get-name
        ()
        (response (string-ascii 32) uint)
    )
    (get-symbol
        ()
        (response (string-ascii 32) uint)
    )
    (get-decimals
        ()
        (response uint uint)
    )
    (get-balance
        (principal)
        (response uint uint)
    )
    (get-total-supply
        ()
        (response uint uint)
    )
))

;; --- Constants ---
(define-constant MAX_BPS u10000) ;; 100% = 10_000 basis points

;; Error codes (uint)
(define-constant ERR-ALREADY-EXISTS u409)
(define-constant ERR-NOT-FOUND u404)
(define-constant ERR-UNAUTHORIZED u401)
(define-constant ERR-INVALID-BPS u422)
(define-constant ERR-INVALID-MIN-CONTRIB u423)

;; --- Storage ---
;; Correct tuple typing (curly braces). Token is a principal constrained to the SIP-010 trait (<sip010-ft>).
(define-map pools
    { pool-id: uint }
    {
        creator: principal,
        token: principal, ;; SIP-010 token contract principal used for premiums/payouts
        total-funds: uint,
        premium-rate-bp: uint, ;; basis points (1% = 100)
        min-contribution: uint,
        active: bool,
    }
)

;; --- Read-only helpers ---
(define-read-only (get-pool (pool-id uint))
    ;; Returns (optional { ...pool tuple... })
    (map-get? pools { pool-id: pool-id })
)

(define-read-only (is-active (pool-id uint))
    (match (map-get? pools { pool-id: pool-id })
        pool (get active pool)
        false
    )
)

(define-read-only (get-total-funds (pool-id uint))
    (match (map-get? pools { pool-id: pool-id })
        pool (get total-funds pool)
        u0
    )
)

;; Example utility: compute premium (amount * bps / 10_000)
(define-read-only (calc-premium
        (amount uint)
        (premium-rate-bp uint)
    )
    (/ (* amount premium-rate-bp) MAX_BPS)
)

;; --- Public functions ---

;; Create a new pool with specified id and parameters.
;; - Validates: pool must not exist, bps <= 10_000, min-contribution > 0
;; - Sets creator to tx-sender, total-funds to 0, active to true
(define-public (create-pool
        (pool-id uint)
        (token principal)
        (premium-rate-bp uint)
        (min-contribution uint)
    )
    (begin
        (asserts! (not (> premium-rate-bp MAX_BPS)) (err ERR-INVALID-BPS))
        (asserts! (not (is-eq min-contribution u0)) (err ERR-INVALID-MIN-CONTRIB))
        (if (map-insert pools { pool-id: pool-id } {
                creator: tx-sender,
                token: token,
                total-funds: u0,
                premium-rate-bp: premium-rate-bp,
                min-contribution: min-contribution,
                active: true,
            })
            (ok pool-id)
            (err ERR-ALREADY-EXISTS)
        )
    )
)

;; Toggle pool active flag. Only the creator may call.
(define-public (set-active
        (pool-id uint)
        (active bool)
    )
    (match (map-get? pools { pool-id: pool-id })
        pool (if (is-eq tx-sender (get creator pool))
            (begin
                (map-set pools { pool-id: pool-id } {
                    creator: (get creator pool),
                    token: (get token pool),
                    total-funds: (get total-funds pool),
                    premium-rate-bp: (get premium-rate-bp pool),
                    min-contribution: (get min-contribution pool),
                    active: active,
                })
                (ok active)
            )
            (err ERR-UNAUTHORIZED)
        )
        (err ERR-NOT-FOUND)
    )
)

;; Update premium-rate-bp and min-contribution. Only the creator may call.
(define-public (update-params
        (pool-id uint)
        (premium-rate-bp uint)
        (min-contribution uint)
    )
    (match (map-get? pools { pool-id: pool-id })
        pool (if (is-eq tx-sender (get creator pool))
            (begin
                (asserts! (not (> premium-rate-bp MAX_BPS)) (err ERR-INVALID-BPS))
                (asserts! (not (is-eq min-contribution u0))
                    (err ERR-INVALID-MIN-CONTRIB)
                )
                (map-set pools { pool-id: pool-id } {
                    creator: (get creator pool),
                    token: (get token pool),
                    total-funds: (get total-funds pool),
                    premium-rate-bp: premium-rate-bp,
                    min-contribution: min-contribution,
                    active: (get active pool),
                })
                (ok true)
            )
            (err ERR-UNAUTHORIZED)
        )
        (err ERR-NOT-FOUND)
    )
)
