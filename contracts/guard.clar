;; Decentralized Insurance Protocol with Enhanced Pool Membership Management

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-initialized (err u101))
(define-constant err-not-initialized (err u102))
(define-constant err-pool-not-found (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-not-member (err u105))
(define-constant err-claim-not-found (err u106))
(define-constant err-invalid-name (err u107))
(define-constant err-invalid-premium (err u108))
(define-constant err-invalid-coverage (err u109))
(define-constant err-invalid-pool-id (err u110))
(define-constant err-invalid-claim-amount (err u111))
(define-constant err-not-admin (err u112))
(define-constant err-invalid-admin (err u113))
(define-constant err-event-not-found (err u114))
(define-constant err-claim-period-expired (err u115))
(define-constant err-invalid-claim-period (err u116))
(define-constant err-already-member (err u117))
(define-constant err-member-not-found (err u118))

;; Define data variables
(define-data-var initialized bool false)
(define-data-var pool-count uint u0)
(define-data-var event-counter uint u0)

;; Define data maps
(define-map pools
  { pool-id: uint }
  {
    name: (string-ascii 50),
    balance: uint,
    premium: uint,
    coverage: uint,
    members: (list 200 principal),
    admin: principal,
    claim-period: uint,
    created-at: uint
  }
)

(define-map claims
  { claim-id: uint }
  {
    pool-id: uint,
    claimant: principal,
    amount: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map events
  { event-id: uint }
  {
    event-type: (string-ascii 20),
    pool-id: (optional uint),
    claim-id: (optional uint),
    user: (optional principal),
    amount: (optional uint)
  }
)

;; Helper function to log events
(define-private (log-event (event-type (string-ascii 20)) 
                           (pool-id (optional uint)) 
                           (claim-id (optional uint))
                           (user (optional principal))
                           (amount (optional uint)))
  (let ((event-id (+ (var-get event-counter) u1)))
    (var-set event-counter event-id)
    (map-set events
      { event-id: event-id }
      {
        event-type: event-type,
        pool-id: pool-id,
        claim-id: claim-id,
        user: user,
        amount: amount
      }
    )
    event-id
  )
)

;; Initialize contract
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get initialized)) err-already-initialized)
    (var-set initialized true)
    (log-event "initialize" none none none none)
    (ok true)
  )
)

;; Create a new insurance pool
(define-public (create-pool (name (string-ascii 50)) (premium uint) (coverage uint) (admin principal) (claim-period uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> (len name) u0) err-invalid-name)
    (asserts! (> premium u0) err-invalid-premium)
    (asserts! (> coverage premium) err-invalid-coverage)
    (asserts! (not (is-eq admin tx-sender)) err-invalid-admin)
    (asserts! (> claim-period u0) err-invalid-claim-period)

    (let (
      (new-pool-id (+ (var-get pool-count) u1))
      (current-time (unwrap-panic (get-block-info? time u0)))
    )
      (map-set pools
        { pool-id: new-pool-id }
        {
          name: name,
          balance: u0,
          premium: premium,
          coverage: coverage,
          members: (list),
          admin: admin,
          claim-period: claim-period,
          created-at: current-time
        }
      )
      (var-set pool-count new-pool-id)
      (log-event "create-pool" (some new-pool-id) none (some admin) none)
      (ok new-pool-id)
    )
  )
)

;; Request to join an insurance pool
(define-public (request-join-pool (pool-id uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> pool-id u0) err-invalid-pool-id)
    (asserts! (<= pool-id (var-get pool-count)) err-pool-not-found)
    
    (let (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
      (premium (get premium pool))
    )
      (asserts! (not (is-some (index-of (get members pool) tx-sender))) err-already-member)
      (asserts! (is-eq (stx-transfer? premium tx-sender (as-contract tx-sender)) (ok true)) err-insufficient-funds)
      (log-event "request-join-pool" (some pool-id) none (some tx-sender) none)
      (ok true)
    )
  )
)

;; Approve join request (admin only)
(define-public (approve-join-request (pool-id uint) (new-member principal))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> pool-id u0) err-invalid-pool-id)
    (asserts! (<= pool-id (var-get pool-count)) err-pool-not-found)

    (let (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
    )
      (asserts! (is-eq tx-sender (get admin pool)) err-not-admin)
      (asserts! (not (is-eq new-member tx-sender)) err-invalid-admin)
      (asserts! (not (is-some (index-of (get members pool) new-member))) err-already-member)

      (map-set pools
        { pool-id: pool-id }
        (merge pool {
          balance: (+ (get balance pool) (get premium pool)),
          members: (unwrap! (as-max-len? (append (get members pool) new-member) u200) err-pool-not-found)
        })
      )
      (log-event "approve-join" (some pool-id) none (some new-member) none)
      (ok true)
    )
  )
)

;; Remove a member from the pool (admin only)
(define-public (remove-member (pool-id uint) (member-to-remove principal))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> pool-id u0) err-invalid-pool-id)
    (asserts! (<= pool-id (var-get pool-count)) err-pool-not-found)

    (let (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
      (member-index (unwrap! (index-of (get members pool) member-to-remove) err-member-not-found))
    )
      (asserts! (is-eq tx-sender (get admin pool)) err-not-admin)
      
      (map-set pools
        { pool-id: pool-id }
        (merge pool {
          members: (unwrap! (as-max-len? (concat (slice (get members pool) u0 member-index)
                                                 (slice (get members pool) (+ u1 member-index) (len (get members pool))))
                                         u200)
                            err-pool-not-found)
        })
      )
      (log-event "remove-member" (some pool-id) none (some member-to-remove) none)
      (ok true)
    )
  )
)

;; File a claim
(define-public (file-claim (pool-id uint) (amount uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> pool-id u0) err-invalid-pool-id)
    (asserts! (<= pool-id (var-get pool-count)) err-pool-not-found)
    (asserts! (> amount u0) err-invalid-claim-amount)
    
    (let (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
      (claim-id (+ (var-get pool-count) u1))
      (current-time (unwrap-panic (get-block-info? time u0)))
    )
      (asserts! (is-some (index-of (get members pool) tx-sender)) err-not-member)
      (asserts! (<= amount (get coverage pool)) err-insufficient-funds)
      (asserts! (<= current-time (+ (get created-at pool) (get claim-period pool))) err-claim-period-expired)
      (map-set claims
        { claim-id: claim-id }
        {
          pool-id: pool-id,
          claimant: tx-sender,
          amount: amount,
          status: "pending",
          created-at: current-time
        }
      )
      (var-set pool-count claim-id)
      (log-event "file-claim" (some pool-id) (some claim-id) (some tx-sender) (some amount))
      (ok claim-id)
    )
  )
)

;; Process a claim (admin only)
(define-public (process-claim (claim-id uint) (approve bool))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> claim-id u0) err-invalid-pool-id)
    (asserts! (<= claim-id (var-get pool-count)) err-claim-not-found)
    
    (let (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
      (pool (unwrap! (map-get? pools { pool-id: (get pool-id claim) }) err-pool-not-found))
      (current-time (unwrap-panic (get-block-info? time u0)))
    )
      (asserts! (is-eq tx-sender (get admin pool)) err-not-admin)
      (asserts! (<= current-time (+ (get created-at claim) (get claim-period pool))) err-claim-period-expired)
      (if approve
        (begin
          (asserts! (>= (get balance pool) (get amount claim)) err-insufficient-funds)
          (map-set pools
            { pool-id: (get pool-id claim) }
            (merge pool { balance: (- (get balance pool) (get amount claim)) })
          )
          (unwrap! (as-contract (stx-transfer? (get amount claim) tx-sender (get claimant claim))) err-insufficient-funds)
          (map-set claims { claim-id: claim-id } (merge claim { status: "approved" }))
          (log-event "process-claim" (some (get pool-id claim)) (some claim-id) (some (get claimant claim)) (some (get amount claim)))
        )
        (begin
          (map-set claims { claim-id: claim-id } (merge claim { status: "rejected" }))
          (log-event "process-claim" (some (get pool-id claim)) (some claim-id) (some (get claimant claim)) none)
        )
      )
      (ok true)
    )
  )
)

;; Change pool administrator
(define-public (change-pool-admin (pool-id uint) (new-admin principal))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> pool-id u0) err-invalid-pool-id)
    (asserts! (<= pool-id (var-get pool-count)) err-pool-not-found)
    (asserts! (not (is-eq new-admin tx-sender)) err-invalid-admin)

    (let (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
    )
      (asserts! (is-eq tx-sender (get admin pool)) err-not-admin)
      (map-set pools
        { pool-id: pool-id }
        (merge pool { admin: new-admin })
      )
      (log-event "change-admin" (some pool-id) none (some new-admin) none)
      (ok true)
    )
  )
)

;; Get pool information
(define-read-only (get-pool-info (pool-id uint))
  (begin
    (asserts! (> pool-id u0) err-invalid-pool-id)
    (asserts! (<= pool-id (var-get pool-count)) err-pool-not-found)
    (ok (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
  )
)

;; Get claim information
(define-read-only (get-claim-info (claim-id uint))
  (begin
    (asserts! (> claim-id u0) err-invalid-pool-id)
    (asserts! (<= claim-id (var-get pool-count)) err-claim-not-found)
    (ok (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
  )
)

;; Get event information
(define-read-only (get-event-info (event-id uint))
  (begin
    (asserts! (> event-id u0) err-invalid-pool-id)
    (asserts! (<= event-id (var-get event-counter)) err-event-not-found)
    (ok (unwrap! (map-get? events { event-id: event-id }) err-event-not-found))
  )
)

;; Get total number of events
(define-read-only (get-event-count)
  (ok (var-get event-counter))
)