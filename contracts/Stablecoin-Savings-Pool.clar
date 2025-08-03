(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_POOL_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_CLAIMED (err u104))
(define-constant ERR_NO_REWARDS_AVAILABLE (err u105))
(define-constant ERR_TRANSFER_FAILED (err u106))
(define-map auto-compound-enabled principal bool)
(define-map auto-compound-total principal uint)

(define-constant ERR_GOAL_NOT_FOUND (err u107))
(define-constant ERR_GOAL_ALREADY_EXISTS (err u108))
(define-constant ERR_GOAL_DEADLINE_PASSED (err u109))

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

(define-read-only (is-auto-compound-enabled (user principal))
  (default-to false (map-get? auto-compound-enabled user))
)

(define-read-only (get-auto-compound-total (user principal))
  (default-to u0 (map-get? auto-compound-total user))
)

(define-public (toggle-auto-compound)
  (let (
    (current-status (is-auto-compound-enabled tx-sender))
  )
    (map-set auto-compound-enabled tx-sender (not current-status))
    (ok (not current-status))
  )
)

(define-public (process-auto-compound (user principal))
  (let (
    (interest-reward (calculate-user-interest user))
    (ubi-reward (calculate-ubi-amount user))
    (total-reward (+ interest-reward ubi-reward))
    (current-deposit (get-user-deposit user))
    (current-pool-balance (var-get total-pool-balance))
    (current-shares (get-user-pool-shares user))
    (current-auto-compound-total (get-auto-compound-total user))
  )
    (asserts! (is-auto-compound-enabled user) ERR_NOT_AUTHORIZED)
    (asserts! (> total-reward u0) ERR_NO_REWARDS_AVAILABLE)
    
    (let (
      (new-deposit (+ current-deposit total-reward))
      (new-shares (if (is-eq current-pool-balance u0)
                    total-reward
                    (/ (* total-reward (ft-get-supply pool-token)) current-pool-balance)))
    )
      (map-set user-deposits user new-deposit)
      (map-set user-pool-shares user (+ current-shares new-shares))
      (map-set user-last-claim user stacks-block-height)
      (map-set auto-compound-total user (+ current-auto-compound-total total-reward))
      (var-set total-pool-balance (+ current-pool-balance total-reward))
      (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) total-reward))
      (try! (ft-mint? pool-token new-shares user))
      (ok total-reward)
    )
  )
)

(define-public (claim-rewards-with-auto-compound)
  (if (is-auto-compound-enabled tx-sender)
    (process-auto-compound tx-sender)
    (claim-rewards)
  )
)

(define-read-only (get-user-stats-with-auto-compound (user principal))
  (merge
    (get-user-stats user)
    {
      auto-compound-enabled: (is-auto-compound-enabled user),
      auto-compound-total: (get-auto-compound-total user)
    }
  )
)


(define-map user-goals {user: principal, goal-id: uint} {target-amount: uint, deadline: uint, bonus-rate: uint, created-at: uint})
(define-map user-goal-progress {user: principal, goal-id: uint} {current-amount: uint, milestone-rewards: uint, completed: bool})
(define-map user-next-goal-id principal uint)

(define-read-only (get-user-goal (user principal) (goal-id uint))
  (map-get? user-goals {user: user, goal-id: goal-id})
)

(define-read-only (get-goal-progress (user principal) (goal-id uint))
  (default-to {current-amount: u0, milestone-rewards: u0, completed: false}
    (map-get? user-goal-progress {user: user, goal-id: goal-id}))
)

(define-read-only (get-next-goal-id (user principal))
  (default-to u1 (map-get? user-next-goal-id user))
)

(define-public (create-savings-goal (target-amount uint) (deadline-blocks uint) (bonus-rate uint))
  (let (
    (goal-id (get-next-goal-id tx-sender))
    (deadline (+ stacks-block-height deadline-blocks))
  )
    (asserts! (> target-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> deadline-blocks u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none (get-user-goal tx-sender goal-id)) ERR_GOAL_ALREADY_EXISTS)
    
    (map-set user-goals 
      {user: tx-sender, goal-id: goal-id}
      {target-amount: target-amount, deadline: deadline, bonus-rate: bonus-rate, created-at: stacks-block-height})
    (map-set user-goal-progress 
      {user: tx-sender, goal-id: goal-id}
      {current-amount: u0, milestone-rewards: u0, completed: false})
    (map-set user-next-goal-id tx-sender (+ goal-id u1))
    (ok goal-id)
  )
)

(define-public (update-goal-progress (user principal) (goal-id uint) (deposit-amount uint))
  (let (
    (goal (unwrap! (get-user-goal user goal-id) ERR_GOAL_NOT_FOUND))
    (progress (get-goal-progress user goal-id))
    (new-amount (+ (get current-amount progress) deposit-amount))
    (milestone-bonus (calculate-milestone-bonus goal progress deposit-amount))
  )
    (asserts! (<= stacks-block-height (get deadline goal)) ERR_GOAL_DEADLINE_PASSED)
    
    (map-set user-goal-progress 
      {user: user, goal-id: goal-id}
      {current-amount: new-amount, 
       milestone-rewards: (+ (get milestone-rewards progress) milestone-bonus),
       completed: (>= new-amount (get target-amount goal))})
    (ok milestone-bonus)
  )
)

(define-read-only (calculate-milestone-bonus (goal {target-amount: uint, deadline: uint, bonus-rate: uint, created-at: uint}) 
                                           (progress {current-amount: uint, milestone-rewards: uint, completed: bool}) 
                                           (deposit-amount uint))
  (let (
    (target (get target-amount goal))
    (current (get current-amount progress))
    (new-total (+ current deposit-amount))
    (quarter-target (/ target u4))
    (half-target (/ target u2))
    (three-quarter-target (/ (* target u3) u4))
  )
    (fold + (list
      (if (and (< current quarter-target) (>= new-total quarter-target)) (/ (* deposit-amount (get bonus-rate goal)) u10000) u0)
      (if (and (< current half-target) (>= new-total half-target)) (/ (* deposit-amount (get bonus-rate goal)) u5000) u0)
      (if (and (< current three-quarter-target) (>= new-total three-quarter-target)) (/ (* deposit-amount (get bonus-rate goal)) u3333) u0)
      (if (and (< current target) (>= new-total target)) (/ (* deposit-amount (get bonus-rate goal)) u2000) u0)
    ) u0)
  )
)

(define-public (claim-goal-rewards (goal-id uint))
  (let (
    (progress (get-goal-progress tx-sender goal-id))
    (milestone-rewards (get milestone-rewards progress))
  )
    (asserts! (> milestone-rewards u0) ERR_NO_REWARDS_AVAILABLE)
    
    (map-set user-goal-progress 
      {user: tx-sender, goal-id: goal-id}
      (merge progress {milestone-rewards: u0}))
    (try! (as-contract (stx-transfer? milestone-rewards tx-sender tx-sender)))
    (ok milestone-rewards)
  )
)