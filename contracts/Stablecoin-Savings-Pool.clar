(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_POOL_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_CLAIMED (err u104))
(define-constant ERR_NO_REWARDS_AVAILABLE (err u105))
(define-constant ERR_TRANSFER_FAILED (err u106))

(define-fungible-token pool-token)

(define-data-var total-pool-balance uint u0)
(define-data-var interest-rate uint u500)
(define-data-var ubi-rate uint u100)
(define-data-var last-reward-block uint u0)
(define-data-var total-rewards-distributed uint u0)

(define-map user-deposits principal uint)
(define-map user-rewards principal uint)
(define-map user-last-claim principal uint)
(define-map ubi-recipients principal bool)
(define-map user-pool-shares principal uint)

(define-read-only (get-pool-balance)
  (var-get total-pool-balance)
)

(define-read-only (get-user-deposit (user principal))
  (default-to u0 (map-get? user-deposits user))
)

(define-read-only (get-user-rewards (user principal))
  (default-to u0 (map-get? user-rewards user))
)

(define-read-only (get-user-pool-shares (user principal))
  (default-to u0 (map-get? user-pool-shares user))
)

(define-read-only (get-interest-rate)
  (var-get interest-rate)
)

(define-read-only (get-ubi-rate)
  (var-get ubi-rate)
)

(define-read-only (is-ubi-recipient (user principal))
  (default-to false (map-get? ubi-recipients user))
)

(define-read-only (get-total-rewards-distributed)
  (var-get total-rewards-distributed)
)

(define-read-only (calculate-user-interest (user principal))
  (let (
    (user-balance (get-user-deposit user))
    (blocks-since-last-claim (- stacks-block-height (default-to stacks-block-height (map-get? user-last-claim user))))
    (interest-per-block (/ (* user-balance (var-get interest-rate)) u1000000))
  )
    (* interest-per-block blocks-since-last-claim)
  )
)

(define-read-only (calculate-ubi-amount (user principal))
  (if (is-ubi-recipient user)
    (let (
      (blocks-since-last-claim (- stacks-block-height (default-to stacks-block-height (map-get? user-last-claim user))))
      (ubi-per-block (var-get ubi-rate))
    )
      (* ubi-per-block blocks-since-last-claim)
    )
    u0
  )
)

(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let (
      (current-deposit (get-user-deposit tx-sender))
      (new-deposit (+ current-deposit amount))
      (current-pool-balance (var-get total-pool-balance))
      (current-shares (get-user-pool-shares tx-sender))
      (new-shares (if (is-eq current-pool-balance u0)
                    amount
                    (/ (* amount (ft-get-supply pool-token)) current-pool-balance)))
    )
      (map-set user-deposits tx-sender new-deposit)
      (map-set user-pool-shares tx-sender (+ current-shares new-shares))
      (var-set total-pool-balance (+ current-pool-balance amount))
      (try! (ft-mint? pool-token new-shares tx-sender))
      (ok true)
    )
  )
)

(define-public (withdraw (amount uint))
  (let (
    (current-deposit (get-user-deposit tx-sender))
    (current-shares (get-user-pool-shares tx-sender))
    (total-supply (ft-get-supply pool-token))
    (pool-balance (var-get total-pool-balance))
    (shares-to-burn (if (is-eq pool-balance u0)
                      u0
                      (/ (* amount total-supply) pool-balance)))
  )
    (asserts! (>= current-deposit amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (>= current-shares shares-to-burn) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set user-deposits tx-sender (- current-deposit amount))
    (map-set user-pool-shares tx-sender (- current-shares shares-to-burn))
    (var-set total-pool-balance (- pool-balance amount))
    (try! (ft-burn? pool-token shares-to-burn tx-sender))
    (ok true)
  )
)

(define-public (claim-rewards)
  (let (
    (interest-reward (calculate-user-interest tx-sender))
    (ubi-reward (calculate-ubi-amount tx-sender))
    (total-reward (+ interest-reward ubi-reward))
    (current-rewards (get-user-rewards tx-sender))
  )
    (asserts! (> total-reward u0) ERR_NO_REWARDS_AVAILABLE)
    
    (map-set user-rewards tx-sender (+ current-rewards total-reward))
    (map-set user-last-claim tx-sender stacks-block-height)
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) total-reward))
    
    (try! (as-contract (stx-transfer? total-reward tx-sender tx-sender)))
    (ok total-reward)
  )
)

(define-public (register-for-ubi)
  (begin
    (map-set ubi-recipients tx-sender true)
    (map-set user-last-claim tx-sender stacks-block-height)
    (ok true)
  )
)

(define-public (unregister-from-ubi)
  (begin
    (map-delete ubi-recipients tx-sender)
    (ok true)
  )
)

(define-public (set-interest-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set interest-rate new-rate)
    (ok true)
  )
)

(define-public (set-ubi-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set ubi-rate new-rate)
    (ok true)
  )
)

(define-public (emergency-withdraw)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (let (
      (contract-balance (stx-get-balance (as-contract tx-sender)))
    )
      (try! (as-contract (stx-transfer? contract-balance tx-sender CONTRACT_OWNER)))
      (ok contract-balance)
    )
  )
)

(define-public (fund-rewards (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (ok true)
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-pool-stats)
  {
    total-pool-balance: (var-get total-pool-balance),
    interest-rate: (var-get interest-rate),
    ubi-rate: (var-get ubi-rate),
    total-rewards-distributed: (var-get total-rewards-distributed),
    contract-balance: (get-contract-balance),
    total-pool-tokens: (ft-get-supply pool-token)
  }
)

(define-read-only (get-user-stats (user principal))
  {
    deposit: (get-user-deposit user),
    rewards: (get-user-rewards user),
    pool-shares: (get-user-pool-shares user),
    pending-interest: (calculate-user-interest user),
    pending-ubi: (calculate-ubi-amount user),
    is-ubi-recipient: (is-ubi-recipient user),
    last-claim-block: (default-to u0 (map-get? user-last-claim user))
  }
)
