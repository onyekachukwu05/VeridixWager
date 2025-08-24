;; VeridixWager: Decentralized Prediction Market Platform

;; Error Constants
(define-constant contract-administrator tx-sender)
(define-constant ERR-UNAUTHORIZED-ACCESS (err u200))
(define-constant ERR-MARKET-COLLISION (err u201))
(define-constant ERR-MARKET-NONEXISTENT (err u202))
(define-constant ERR-MARKET-SEALED (err u203))
(define-constant ERR-CAPITAL-SHORTAGE (err u204))
(define-constant ERR-MARKET-FINALIZED (err u205))
(define-constant ERR-MARKET-PREMATURE-CLOSE (err u206))
(define-constant ERR-MARKET-IMMUTABLE (err u207))
(define-constant ERR-INVALID-SCENARIO-COUNT (err u208))
(define-constant ERR-INVALID-TERMINUS-BLOCK (err u209))
(define-constant ERR-INVALID-MECHANISM-TYPE (err u210))
(define-constant ERR-MISSING-PROBABILITY-DATA (err u211))
(define-constant ERR-INVALID-SCENARIO-CHOICE (err u212))
(define-constant ERR-MARKET-ELAPSED (err u213))
(define-constant ERR-NO-VICTORIOUS-SCENARIOS (err u214))
(define-constant ERR-EXCESSIVE-VICTORS (err u215))
(define-constant ERR-INVALID-VICTOR-ASSIGNMENT (err u216))
(define-constant ERR-NON-VICTORIOUS-SELECTION (err u217))
(define-constant ERR-DISTRIBUTION-FAILURE (err u218))
(define-constant ERR-REIMBURSEMENT-ACTIVE (err u219))
(define-constant ERR-INVALID-MARKET-SYNOPSIS (err u220))
(define-constant ERR-INVALID-STAKE-MAGNITUDE (err u221))

;; Data variables
(define-data-var next-market-id uint u0)

;; Prediction mechanisms
(define-data-var supported-mechanisms (list 10 (string-ascii 20)) (list "absolute-winner" "proportional-share" "fixed-probability"))

;; Define market structure
(define-map prediction-markets
    { market-id: uint }
    {
        architect: principal,
        synopsis: (string-ascii 256),
        scenarios: (list 10 (string-ascii 64)),
        total-liquidity: uint,
        operational: bool,
        victorious-scenarios: (list 5 uint),
        terminus-block: uint,
        mechanism-type: (string-ascii 20),
        probabilities: (optional (list 10 uint)),
    }
)

;; Define participant stakes structure
(define-map participant-stakes
    {
        market-id: uint,
        participant: principal,
    }
    {
        selected-scenario: uint,
        stake-magnitude: uint,
    }
)

;; Read-only functions

(define-read-only (get-prediction-market (market-id uint))
    (map-get? prediction-markets { market-id: market-id })
)

(define-read-only (get-participant-stake
        (market-id uint)
        (participant principal)
    )
    (map-get? participant-stakes {
        market-id: market-id,
        participant: participant,
    })
)

(define-read-only (get-current-block-height)
    block-height
)

;; Private functions

(define-private (calculate-distribution
        (market {
            architect: principal,
            synopsis: (string-ascii 256),
            scenarios: (list 10 (string-ascii 64)),
            total-liquidity: uint,
            operational: bool,
            victorious-scenarios: (list 5 uint),
            terminus-block: uint,
            mechanism-type: (string-ascii 20),
            probabilities: (optional (list 10 uint)),
        })
        (stake {
            selected-scenario: uint,
            stake-magnitude: uint,
        })
        (victors (list 5 uint))
    )
    (let (
            (mechanism (get mechanism-type market))
            (total-market-liquidity (get total-liquidity market))
            (participant-magnitude (get stake-magnitude stake))
        )
        (if (is-eq mechanism "absolute-winner")
            ;; For absolute-winner, divide total pool by number of winning scenarios
            (/ total-market-liquidity (len victors))
            (if (is-eq mechanism "proportional-share")
                ;; For proportional-share, payout based on stake ratio
                (/ (* participant-magnitude total-market-liquidity)
                    total-market-liquidity
                )
                ;; Fixed-probability payout
                (let (
                        (probability-list (unwrap! (get probabilities market) u0))
                        (selected-probability (unwrap!
                            (element-at probability-list
                                (- (get selected-scenario stake) u1)
                            )
                            u0
                        ))
                    )
                    (+ participant-magnitude
                        (* participant-magnitude (/ selected-probability u100))
                    )
                )
            )
        )
    )
)

(define-private (get-stake-for-scenario
        (scenario-id uint)
        (market-id uint)
    )
    (let ((participant-stake (get-participant-stake market-id tx-sender)))
        (if (is-some participant-stake)
            (let ((stake-details (unwrap! participant-stake u0)))
                (if (is-eq (get selected-scenario stake-details) scenario-id)
                    (get stake-magnitude stake-details)
                    u0
                )
            )
            u0
        )
    )
)

(define-private (get-total-stake-on-scenario (scenario-id uint))
    (get-stake-for-scenario scenario-id (var-get next-market-id))
)

(define-private (process-reimbursements (market-id uint))
    (let ((participant-stake (get-participant-stake market-id tx-sender)))
        (match participant-stake
            stake-details (match (as-contract (stx-transfer? (get stake-magnitude stake-details) tx-sender
                tx-sender
            ))
                success (begin
                    (map-delete participant-stakes {
                        market-id: market-id,
                        participant: tx-sender,
                    })
                    (ok true)
                )
                error
                ERR-DISTRIBUTION-FAILURE
            )
            ERR-REIMBURSEMENT-ACTIVE
        )
    )
)

(define-private (validate-victors
        (victors (list 5 uint))
        (max-valid-scenario uint)
    )
    (let (
            (first-scenario (element-at victors u0))
            (second-scenario (element-at victors u1))
            (third-scenario (element-at victors u2))
            (fourth-scenario (element-at victors u3))
            (fifth-scenario (element-at victors u4))
        )
        (and
            ;; Check if first scenario exists and is valid
            (match first-scenario
                value (and (> value u0) (<= value max-valid-scenario))
                true
            )
            ;; For remaining scenarios, they're either valid or none
            (match second-scenario
                value (and (> value u0) (<= value max-valid-scenario))
                true
            )
            (match third-scenario
                value (and (> value u0) (<= value max-valid-scenario))
                true
            )
            (match fourth-scenario
                value (and (> value u0) (<= value max-valid-scenario))
                true
            )
            (match fifth-scenario
                value (and (> value u0) (<= value max-valid-scenario))
                true
            )
        )
    )
)

;; Public functions

(define-public (architect-prediction-market
        (synopsis (string-ascii 256))
        (scenarios (list 10 (string-ascii 64)))
        (terminus-block uint)
        (mechanism-type (string-ascii 20))
        (probabilities (optional (list 10 uint)))
    )
    (let ((new-market-id (var-get next-market-id)))
        (asserts! (> (len synopsis) u0) ERR-INVALID-MARKET-SYNOPSIS)
        (asserts! (> (len scenarios) u1) ERR-INVALID-SCENARIO-COUNT)
        (asserts! (> terminus-block block-height) ERR-INVALID-TERMINUS-BLOCK)
        (asserts!
            (is-some (index-of (var-get supported-mechanisms) mechanism-type))
            ERR-INVALID-MECHANISM-TYPE
        )
        (asserts!
            (or
                (is-eq mechanism-type "absolute-winner")
                (is-eq mechanism-type "proportional-share")
                (is-some probabilities)
            )
            ERR-MISSING-PROBABILITY-DATA
        )
        (map-set prediction-markets { market-id: new-market-id } {
            architect: tx-sender,
            synopsis: synopsis,
            scenarios: scenarios,
            total-liquidity: u0,
            operational: true,
            victorious-scenarios: (list),
            terminus-block: terminus-block,
            mechanism-type: mechanism-type,
            probabilities: probabilities,
        })
        (var-set next-market-id (+ new-market-id u1))
        (ok new-market-id)
    )
)

(define-public (commit-prediction
        (market-id uint)
        (selected-scenario uint)
        (stake-magnitude uint)
    )
    (let (
            (market (unwrap! (get-prediction-market market-id) ERR-MARKET-NONEXISTENT))
            (existing-stake (default-to {
                selected-scenario: u0,
                stake-magnitude: u0,
            }
                (get-participant-stake market-id tx-sender)
            ))
        )
        (asserts! (> stake-magnitude u0) ERR-INVALID-STAKE-MAGNITUDE)
        (asserts! (get operational market) ERR-MARKET-SEALED)
        (asserts! (>= (len (get scenarios market)) selected-scenario)
            ERR-INVALID-SCENARIO-CHOICE
        )
        (asserts! (< block-height (get terminus-block market)) ERR-MARKET-ELAPSED)
        (try! (stx-transfer? stake-magnitude tx-sender (as-contract tx-sender)))
        (map-set participant-stakes {
            market-id: market-id,
            participant: tx-sender,
        } {
            selected-scenario: selected-scenario,
            stake-magnitude: (+ stake-magnitude (get stake-magnitude existing-stake)),
        })
        (map-set prediction-markets { market-id: market-id }
            (merge market { total-liquidity: (+ (get total-liquidity market) stake-magnitude) })
        )
        (ok true)
    )
)

(define-public (seal-prediction-market (market-id uint))
    (let ((market (unwrap! (get-prediction-market market-id) ERR-MARKET-NONEXISTENT)))
        (asserts!
            (or (is-eq (get architect market) tx-sender) (is-eq contract-administrator tx-sender))
            ERR-UNAUTHORIZED-ACCESS
        )
        (asserts! (get operational market) ERR-MARKET-SEALED)
        (asserts! (>= block-height (get terminus-block market))
            ERR-MARKET-PREMATURE-CLOSE
        )
        (map-set prediction-markets { market-id: market-id }
            (merge market { operational: false })
        )
        (ok true)
    )
)

(define-public (nullify-prediction-market (market-id uint))
    (let ((market (unwrap! (get-prediction-market market-id) ERR-MARKET-NONEXISTENT)))
        (asserts! (is-eq (get architect market) tx-sender)
            ERR-UNAUTHORIZED-ACCESS
        )
        (asserts! (get operational market) ERR-MARKET-SEALED)
        (asserts! (< block-height (get terminus-block market))
            ERR-MARKET-IMMUTABLE
        )

        ;; First set the market as sealed
        (map-set prediction-markets { market-id: market-id }
            (merge market { operational: false })
        )

        ;; Then process reimbursements
        (process-reimbursements market-id)
    )
)

(define-public (harvest-returns (market-id uint))
    (let (
            (market (unwrap! (get-prediction-market market-id) ERR-MARKET-NONEXISTENT))
            (participant-stake (unwrap! (get-participant-stake market-id tx-sender)
                ERR-MARKET-NONEXISTENT
            ))
            (victorious-scenarios (get victorious-scenarios market))
        )
        (asserts!
            (is-some (index-of victorious-scenarios
                (get selected-scenario participant-stake)
            ))
            ERR-NON-VICTORIOUS-SELECTION
        )
        (let ((distribution-amount (calculate-distribution market participant-stake victorious-scenarios)))
            (try! (as-contract (stx-transfer? distribution-amount tx-sender tx-sender)))
            (map-delete participant-stakes {
                market-id: market-id,
                participant: tx-sender,
            })
            (ok distribution-amount)
        )
    )
)

(define-public (adjudicate-market
        (market-id uint)
        (victorious-scenarios (list 5 uint))
    )
    (let ((market (unwrap! (get-prediction-market market-id) ERR-MARKET-NONEXISTENT)))
        (asserts! (is-eq contract-administrator tx-sender)
            ERR-UNAUTHORIZED-ACCESS
        )
        (asserts! (not (get operational market)) ERR-MARKET-SEALED)
        (asserts! (is-eq (len (get victorious-scenarios market)) u0)
            ERR-MARKET-FINALIZED
        )
        (asserts! (> (len victorious-scenarios) u0) ERR-NO-VICTORIOUS-SCENARIOS)
        (asserts! (<= (len victorious-scenarios) u5) ERR-EXCESSIVE-VICTORS)

        ;; Validate each victorious scenario
        (asserts!
            (validate-victors victorious-scenarios (len (get scenarios market)))
            ERR-INVALID-VICTOR-ASSIGNMENT
        )

        (map-set prediction-markets { market-id: market-id }
            (merge market { victorious-scenarios: victorious-scenarios })
        )
        (ok true)
    )
)

;; Contract initialization
(begin
    (var-set next-market-id u0)
)
;; Export the Component function
(define-public (Component)
    (ok true)
)
