;; Decentralized Insurance Protocol with Pool Administrator Role

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

;; Define data variables
(define-data-var initialized bool false)
(define-data-var pool-count uint u0)

;; Define data maps
(define-map pools
  { pool-id: uint }
  {
    name: (string-ascii 50),
    balance: uint,
    premium: uint,
    coverage: uint,
    members: (list 200 principal),
    admin: principal
  }
)

(define-map claims
  { claim-id: uint }
  {
    pool-id: uint,
    claimant: principal,
    amount: uint,
    status: (string-ascii 20)
  }
)

;; Initialize contract
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get initialized)) err-already-initialized)
    (var-set initialized true)
    (ok true)
  )
)

;; Create a new insurance pool
(define-public (create-pool (name (string-ascii 50)) (premium uint) (coverage uint) (admin principal))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> (len name) u0) err-invalid-name)
    (asserts! (> premium u0) err-invalid-premium)
    (asserts! (> coverage premium) err-invalid-coverage)
    
    (let ((new-pool-id (+ (var-get pool-count) u1)))
      (map-set pools
        { pool-id: new-pool-id }
        {
          name: name,
          balance: u0,
          premium: premium,
          coverage: coverage,
          members: (list),
          admin: admin
        }
      )
      (var-set pool-count new-pool-id)
      (ok new-pool-id)
    )
  )
)

;; Join an insurance pool (now requires admin approval)
(define-public (request-join-pool (pool-id uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> pool-id u0) err-invalid-pool-id)
    (asserts! (<= pool-id (var-get pool-count)) err-pool-not-found)
    
    (let (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
      (premium (get premium pool))
    )
      (asserts! (is-eq (stx-transfer? premium tx-sender (as-contract tx-sender)) (ok true)) err-insufficient-funds)
      (ok true)
    )
  )
)

;; Approve join request (admin only)
(define-public (approve-join-request (pool-id uint) (new-member principal))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (let (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
    )
      (asserts! (is-eq tx-sender (get admin pool)) err-not-admin)
      (map-set pools
        { pool-id: pool-id }
        (merge pool {
          balance: (+ (get balance pool) (get premium pool)),
          members: (unwrap! (as-max-len? (append (get members pool) new-member) u200) err-pool-not-found)
        })
      )
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
    )
      (asserts! (is-some (index-of (get members pool) tx-sender)) err-not-member)
      (asserts! (<= amount (get coverage pool)) err-insufficient-funds)
      (map-set claims
        { claim-id: claim-id }
        {
          pool-id: pool-id,
          claimant: tx-sender,
          amount: amount,
          status: "pending"
        }
      )
      (var-set pool-count claim-id)
      (ok claim-id)
    )
  )
)

;; Process a claim (now admin only)
(define-public (process-claim (claim-id uint) (approve bool))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (> claim-id u0) err-invalid-pool-id)
    (asserts! (<= claim-id (var-get pool-count)) err-claim-not-found)
    
    (let (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
      (pool (unwrap! (map-get? pools { pool-id: (get pool-id claim) }) err-pool-not-found))
    )
      (asserts! (is-eq tx-sender (get admin pool)) err-not-admin)
      (if approve
        (begin
          (asserts! (>= (get balance pool) (get amount claim)) err-insufficient-funds)
          (map-set pools
            { pool-id: (get pool-id claim) }
            (merge pool { balance: (- (get balance pool) (get amount claim)) })
          )
          (unwrap! (as-contract (stx-transfer? (get amount claim) tx-sender (get claimant claim))) err-insufficient-funds)
          (map-set claims { claim-id: claim-id } (merge claim { status: "approved" }))
        )
        (map-set claims { claim-id: claim-id } (merge claim { status: "rejected" }))
      )
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

;; Change pool administrator
(define-public (change-pool-admin (pool-id uint) (new-admin principal))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (let (
      (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
    )
      (asserts! (is-eq tx-sender (get admin pool)) err-not-admin)
      (map-set pools
        { pool-id: pool-id }
        (merge pool { admin: new-admin })
      )
      (ok true)
    )
  )
)