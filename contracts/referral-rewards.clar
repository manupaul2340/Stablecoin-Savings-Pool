(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_INVALID_AMOUNT (err u201))
(define-constant ERR_ALREADY_REFERRED (err u202))
(define-constant ERR_CANNOT_REFER_SELF (err u203))
(define-constant ERR_NO_REWARDS (err u204))
(define-constant ERR_INVALID_RATE (err u205))

(define-data-var referrer-bonus-rate uint u500)
(define-data-var referee-bonus-rate uint u300)
(define-data-var min-deposit-for-bonus uint u1000000)
(define-data-var total-referral-rewards uint u0)

(define-map user-referrer principal principal)
(define-map referrer-stats principal {total-referrals: uint, total-earned: uint})
(define-map referee-claimed principal bool)
(define-map pending-rewards principal uint)

(define-read-only (get-referrer (user principal))
  (map-get? user-referrer user)
)

(define-read-only (get-referrer-stats (referrer principal))
  (default-to {total-referrals: u0, total-earned: u0}
    (map-get? referrer-stats referrer))
)

(define-read-only (get-pending-rewards (user principal))
  (default-to u0 (map-get? pending-rewards user))
)

(define-read-only (has-claimed-referee-bonus (user principal))
  (default-to false (map-get? referee-claimed user))
)

(define-read-only (get-bonus-rates)
  {
    referrer-bonus: (var-get referrer-bonus-rate),
    referee-bonus: (var-get referee-bonus-rate),
    min-deposit: (var-get min-deposit-for-bonus)
  }
)

(define-public (set-referrer (referrer principal))
  (begin
    (asserts! (not (is-eq tx-sender referrer)) ERR_CANNOT_REFER_SELF)
    (asserts! (is-none (get-referrer tx-sender)) ERR_ALREADY_REFERRED)
    (map-set user-referrer tx-sender referrer)
    (ok true)
  )
)

(define-public (process-referral-bonus (referee principal) (deposit-amount uint))
  (match (get-referrer referee)
    referrer (if (and (>= deposit-amount (var-get min-deposit-for-bonus))
                     (not (has-claimed-referee-bonus referee)))
      (let (
        (referrer-reward (/ (* deposit-amount (var-get referrer-bonus-rate)) u10000))
        (referee-reward (/ (* deposit-amount (var-get referee-bonus-rate)) u10000))
        (stats (get-referrer-stats referrer))
        (current-referrer-pending (get-pending-rewards referrer))
        (current-referee-pending (get-pending-rewards referee))
      )
        (map-set pending-rewards referrer (+ current-referrer-pending referrer-reward))
        (map-set pending-rewards referee (+ current-referee-pending referee-reward))
        (map-set referee-claimed referee true)
        (map-set referrer-stats referrer {
          total-referrals: (+ (get total-referrals stats) u1),
          total-earned: (+ (get total-earned stats) referrer-reward)
        })
        (var-set total-referral-rewards (+ (var-get total-referral-rewards) (+ referrer-reward referee-reward)))
        (ok {referrer-reward: referrer-reward, referee-reward: referee-reward})
      )
      (ok {referrer-reward: u0, referee-reward: u0}))
    (ok {referrer-reward: u0, referee-reward: u0}))
)

(define-public (claim-referral-rewards)
  (let (
    (rewards (get-pending-rewards tx-sender))
  )
    (asserts! (> rewards u0) ERR_NO_REWARDS)
    (map-set pending-rewards tx-sender u0)
    (try! (as-contract (stx-transfer? rewards tx-sender tx-sender)))
    (ok rewards)
  )
)

(define-public (set-referrer-bonus-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= new-rate u2000) ERR_INVALID_RATE)
    (var-set referrer-bonus-rate new-rate)
    (ok true)
  )
)

(define-public (set-referee-bonus-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= new-rate u2000) ERR_INVALID_RATE)
    (var-set referee-bonus-rate new-rate)
    (ok true)
  )
)

(define-public (set-min-deposit (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set min-deposit-for-bonus amount)
    (ok true)
  )
)

(define-public (fund-referral-pool (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (ok true)
  )
)