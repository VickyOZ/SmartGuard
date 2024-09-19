;; Decentralized Insurance Protocol

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-initialized (err u101))
(define-constant err-not-initialized (err u102))
(define-constant err-pool-not-found (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-not-member (err u105))
(define-constant err-claim-not-found (err u106))

;; Define data variables
(define-data-var initialized bool false)

;; Define data maps
(define-map pools
  { pool-id: uint }
  {
    name: (string-ascii 50),
    balance: uint,
    premium: uint,
    coverage: uint,
    members: (list 200 principal)
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
(define-public (create-pool (name (string-ascii 50)) (premium uint) (coverage uint))
  (let ((pool-id (+ (len (map-keys pools)) u1)))
    (asserts! (var-get initialized) err-not-initialized)
    (map-set pools
      { pool-id: pool-id }
      {
        name: name,
        balance: u0,
        premium: premium,
        coverage: coverage,
        members: (list)
      }
    )
    (ok pool-id)
  )
)

;; Join an insurance pool
(define-public (join-pool (pool-id uint))
  (let (
    (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
    (premium (get premium pool))
  )
    (asserts! (is-eq (stx-transfer? premium tx-sender (as-contract tx-sender)) (ok true)) err-insufficient-funds)
    (map-set pools
      { pool-id: pool-id }
      (merge pool {
        balance: (+ (get balance pool) premium),
        members: (unwrap! (as-max-len? (append (get members pool) tx-sender) u200) err-pool-not-found)
      })
    )
    (ok true)
  )
)

;; File a claim
(define-public (file-claim (pool-id uint) (amount uint))
  (let (
    (pool (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found))
    (claim-id (+ (len (map-keys claims)) u1))
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
    (ok claim-id)
  )
)

;; Process a claim (simplified for demonstration)
(define-public (process-claim (claim-id uint) (approve bool))
  (let (
    (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
    (pool (unwrap! (map-get? pools { pool-id: (get pool-id claim) }) err-pool-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
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

;; Get pool information
(define-read-only (get-pool-info (pool-id uint))
  (map-get? pools { pool-id: pool-id })
)

;; Get claim information
(define-read-only (get-claim-info (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)