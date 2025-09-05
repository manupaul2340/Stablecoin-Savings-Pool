(define-constant ERR_LOCK_NOT_FOUND (err u110))
(define-constant ERR_LOCK_STILL_ACTIVE (err u111))
(define-constant ERR_INVALID_LOCK_PERIOD (err u112))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))

(define-map user-time-locks {user: principal, lock-id: uint} 
  {amount: uint, unlock-block: uint, lock-period: uint, bonus-multiplier: uint, created-at: uint})
(define-map user-next-lock-id principal uint)
(define-map total-locked-by-user principal uint)

(define-data-var penalty-rate uint u2000)

(define-read-only (get-lock-bonus-multiplier (lock-period uint))
  (if (is-eq lock-period u4320)
    u1500
    (if (is-eq lock-period u12960)
      u2000
      (if (is-eq lock-period u25920)
        u3000
        (if (is-eq lock-period u52560)
          u5000
          u1000))))
)

(define-read-only (get-user-lock (user principal) (lock-id uint))
  (map-get? user-time-locks {user: user, lock-id: lock-id})
)

(define-read-only (get-next-lock-id (user principal))
  (default-to u1 (map-get? user-next-lock-id user))
)

(define-read-only (get-total-locked (user principal))
  (default-to u0 (map-get? total-locked-by-user user))
)

(define-read-only (is-lock-expired (user principal) (lock-id uint))
  (match (get-user-lock user lock-id)
    lock (>= stacks-block-height (get unlock-block lock))
    false)
)

(define-public (create-time-lock (amount uint) (lock-period uint))
  (let (
    (lock-id (get-next-lock-id tx-sender))
    (unlock-block (+ stacks-block-height lock-period))
    (bonus-multiplier (get-lock-bonus-multiplier lock-period))
    (current-locked (get-total-locked tx-sender))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (or (is-eq lock-period u4320) (is-eq lock-period u12960) 
                  (is-eq lock-period u25920) (is-eq lock-period u52560)) ERR_INVALID_LOCK_PERIOD)
    
    (map-set user-time-locks 
      {user: tx-sender, lock-id: lock-id}
      {amount: amount, unlock-block: unlock-block, lock-period: lock-period, 
       bonus-multiplier: bonus-multiplier, created-at: stacks-block-height})
    (map-set user-next-lock-id tx-sender (+ lock-id u1))
    (map-set total-locked-by-user tx-sender (+ current-locked amount))
    (ok lock-id)
  )
)

(define-public (unlock-time-lock (lock-id uint))
  (let (
    (lock (unwrap! (get-user-lock tx-sender lock-id) ERR_LOCK_NOT_FOUND))
    (current-locked (get-total-locked tx-sender))
  )
    (asserts! (>= stacks-block-height (get unlock-block lock)) ERR_LOCK_STILL_ACTIVE)
    
    (map-delete user-time-locks {user: tx-sender, lock-id: lock-id})
    (map-set total-locked-by-user tx-sender (- current-locked (get amount lock)))
    (ok (get amount lock))
  )
)

(define-public (emergency-unlock (lock-id uint))
  (let (
    (lock (unwrap! (get-user-lock tx-sender lock-id) ERR_LOCK_NOT_FOUND))
    (penalty-amount (/ (* (get amount lock) (var-get penalty-rate)) u10000))
    (withdrawable-amount (- (get amount lock) penalty-amount))
    (current-locked (get-total-locked tx-sender))
  )
    (map-delete user-time-locks {user: tx-sender, lock-id: lock-id})
    (map-set total-locked-by-user tx-sender (- current-locked (get amount lock)))
    (ok withdrawable-amount)
  )
)

(define-read-only (calculate-locked-bonus (user principal) (lock-id uint))
  (match (get-user-lock user lock-id)
    lock (let (
      (base-amount (get amount lock))
      (multiplier (get bonus-multiplier lock))
      (blocks-since-creation (- stacks-block-height (get created-at lock)))
    )
      (/ (* base-amount (* multiplier blocks-since-creation)) u10000000)
    )
    u0)
)

(define-read-only (get-lock-stats (user principal))
  {
    total-locked: (get-total-locked user),
    next-lock-id: (get-next-lock-id user),
    penalty-rate: (var-get penalty-rate)
  }
)
