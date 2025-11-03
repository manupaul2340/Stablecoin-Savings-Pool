(define-constant ERR_NOT_AUTHORIZED (err u300))
(define-constant ERR_INVALID_TIER (err u301))
(define-constant ERR_TIER_LOCKED (err u302))

(define-constant BRONZE_THRESHOLD u0)
(define-constant SILVER_THRESHOLD u144)
(define-constant GOLD_THRESHOLD u4320)
(define-constant PLATINUM_THRESHOLD u25920)

(define-constant BRONZE_MULTIPLIER u10000)
(define-constant SILVER_MULTIPLIER u11000)
(define-constant GOLD_MULTIPLIER u12500)
(define-constant PLATINUM_MULTIPLIER u15000)

(define-constant BRONZE_FEE_DISCOUNT u0)
(define-constant SILVER_FEE_DISCOUNT u2500)
(define-constant GOLD_FEE_DISCOUNT u5000)
(define-constant PLATINUM_FEE_DISCOUNT u7500)

(define-map user-tier-data principal 
  {tier: uint, tier-entry-block: uint, consecutive-blocks: uint, lifetime-blocks: uint})
(define-map user-tier-rewards principal uint)
(define-data-var total-tier-rewards-distributed uint u0)

(define-read-only (get-tier-name (tier-level uint))
  (if (is-eq tier-level u0) "Bronze"
    (if (is-eq tier-level u1) "Silver"
      (if (is-eq tier-level u2) "Gold"
        (if (is-eq tier-level u3) "Platinum" "Unknown"))))
)

(define-read-only (get-tier-multiplier (tier-level uint))
  (if (is-eq tier-level u3) PLATINUM_MULTIPLIER
    (if (is-eq tier-level u2) GOLD_MULTIPLIER
      (if (is-eq tier-level u1) SILVER_MULTIPLIER BRONZE_MULTIPLIER)))
)

(define-read-only (get-tier-fee-discount (tier-level uint))
  (if (is-eq tier-level u3) PLATINUM_FEE_DISCOUNT
    (if (is-eq tier-level u2) GOLD_FEE_DISCOUNT
      (if (is-eq tier-level u1) SILVER_FEE_DISCOUNT BRONZE_FEE_DISCOUNT)))
)

(define-read-only (get-user-tier-data (user principal))
  (default-to {tier: u0, tier-entry-block: stacks-block-height, 
               consecutive-blocks: u0, lifetime-blocks: u0}
    (map-get? user-tier-data user))
)

(define-read-only (get-user-tier-rewards (user principal))
  (default-to u0 (map-get? user-tier-rewards user))
)

(define-read-only (calculate-tier (consecutive-blocks uint))
  (if (>= consecutive-blocks PLATINUM_THRESHOLD) u3
    (if (>= consecutive-blocks GOLD_THRESHOLD) u2
      (if (>= consecutive-blocks SILVER_THRESHOLD) u1 u0)))
)

(define-public (update-tier-progress (user principal) (is-active bool))
  (let (
    (current-data (get-user-tier-data user))
    (new-consecutive (if is-active (+ (get consecutive-blocks current-data) u1) u0))
    (new-lifetime (if is-active (+ (get lifetime-blocks current-data) u1) 
                                 (get lifetime-blocks current-data)))
    (new-tier (calculate-tier new-consecutive))
    (old-tier (get tier current-data))
  )
    (map-set user-tier-data user {
      tier: new-tier,
      tier-entry-block: (if (> new-tier old-tier) stacks-block-height 
                           (get tier-entry-block current-data)),
      consecutive-blocks: new-consecutive,
      lifetime-blocks: new-lifetime
    })
    (ok new-tier)
  )
)

(define-public (claim-tier-bonus (bonus-amount uint))
  (let (
    (current-rewards (get-user-tier-rewards tx-sender))
  )
    (map-set user-tier-rewards tx-sender (+ current-rewards bonus-amount))
    (var-set total-tier-rewards-distributed 
             (+ (var-get total-tier-rewards-distributed) bonus-amount))
    (ok bonus-amount)
  )
)

(define-read-only (get-tier-stats (user principal))
  (let (
    (tier-data (get-user-tier-data user))
  )
    (merge tier-data {
      tier-name: (get-tier-name (get tier tier-data)),
      multiplier: (get-tier-multiplier (get tier tier-data)),
      fee-discount: (get-tier-fee-discount (get tier tier-data)),
      tier-rewards: (get-user-tier-rewards user),
      blocks-to-next-tier: (get-blocks-to-next-tier tier-data)
    })
  )
)

(define-read-only (get-blocks-to-next-tier (tier-data {tier: uint, tier-entry-block: uint, 
                                                        consecutive-blocks: uint, lifetime-blocks: uint}))
  (let ((current-tier (get tier tier-data))
        (consecutive (get consecutive-blocks tier-data)))
    (if (is-eq current-tier u3) u0
      (if (is-eq current-tier u2) (- PLATINUM_THRESHOLD consecutive)
        (if (is-eq current-tier u1) (- GOLD_THRESHOLD consecutive)
          (- SILVER_THRESHOLD consecutive)))))
)
