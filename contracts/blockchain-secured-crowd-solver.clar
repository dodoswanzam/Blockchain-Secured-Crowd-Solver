(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-insufficient-stake (err u105))
(define-constant err-invalid-status (err u106))
(define-constant err-deadline-passed (err u107))
(define-constant err-verification-failed (err u108))
(define-constant err-insufficient-votes (err u109))

(define-data-var next-problem-id uint u1)
(define-data-var next-solution-id uint u1)
(define-data-var next-solver-id uint u1)
(define-data-var platform-fee uint u25)
(define-data-var min-solver-stake uint u1500)
(define-data-var min-verification-votes uint u3)
(define-data-var verification-threshold uint u80)

(define-map problems uint {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    difficulty-rating: uint,
    reward-amount: uint,
    deadline: uint,
    status: (string-ascii 20),
    solution-count: uint,
    verification-required: bool,
    security-level: uint,
    created-at: uint
})

(define-map solutions uint {
    problem-id: uint,
    solver-id: uint,
    solution-data: (string-ascii 400),
    implementation-proof: (string-ascii 200),
    confidence-score: uint,
    verification-status: (string-ascii 20),
    votes-received: uint,
    security-verified: bool,
    submitted-at: uint,
    reward-claimed: bool
})

(define-map crowd-solvers uint {
    owner: principal,
    solver-name: (string-ascii 50),
    expertise-domains: (list 5 (string-ascii 30)),
    reputation-score: uint,
    problems-solved: uint,
    stake-amount: uint,
    is-verified: bool,
    security-clearance: uint,
    total-rewards-earned: uint,
    success-rate: uint
})

(define-map solution-verifications {solution-id: uint, verifier: principal} {
    verification-score: uint,
    security-assessment: uint,
    implementation-check: bool,
    reasoning: (string-ascii 200),
    verified-at: uint
})

(define-map problem-security-requirements uint {
    encryption-required: bool,
    access-control-level: uint,
    audit-trail-required: bool,
    multi-sig-verification: bool,
    security-deposit: uint
})

(define-map solver-specializations {solver-id: uint, domain: (string-ascii 30)} {
    proficiency-level: uint,
    problems-solved-in-domain: uint,
    domain-reputation: uint,
    certification-verified: bool
})

(define-map crowd-voting {problem-id: uint, voter: principal} {
    preferred-solution-id: uint,
    vote-weight: uint,
    voting-reasoning: (string-ascii 150),
    cast-at: uint
})

(define-public (register-crowd-solver 
    (solver-name (string-ascii 50))
    (expertise-domains (list 5 (string-ascii 30)))
    (stake-amount uint))
    (let ((solver-id (var-get next-solver-id)))
        (asserts! (>= stake-amount (var-get min-solver-stake)) err-insufficient-stake)
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        (map-set crowd-solvers solver-id {
            owner: tx-sender,
            solver-name: solver-name,
            expertise-domains: expertise-domains,
            reputation-score: u100,
            problems-solved: u0,
            stake-amount: stake-amount,
            is-verified: false,
            security-clearance: u50,
            total-rewards-earned: u0,
            success-rate: u0
        })
        (var-set next-solver-id (+ solver-id u1))
        (ok solver-id)))

(define-public (create-secured-problem
    (title (string-ascii 100))
    (description (string-ascii 500))
    (category (string-ascii 50))
    (difficulty-rating uint)
    (reward-amount uint)
    (deadline uint)
    (verification-required bool)
    (security-level uint))
    (let ((problem-id (var-get next-problem-id)))
        (asserts! (>= reward-amount u100) err-invalid-amount)
        (asserts! (> deadline stacks-block-height) err-deadline-passed)
        (try! (stx-transfer? reward-amount tx-sender (as-contract tx-sender)))
        (map-set problems problem-id {
            creator: tx-sender,
            title: title,
            description: description,
            category: category,
            difficulty-rating: difficulty-rating,
            reward-amount: reward-amount,
            deadline: deadline,
            status: "active",
            solution-count: u0,
            verification-required: verification-required,
            security-level: security-level,
            created-at: stacks-block-height
        })
        (map-set problem-security-requirements problem-id {
            encryption-required: (> security-level u70),
            access-control-level: security-level,
            audit-trail-required: verification-required,
            multi-sig-verification: (> security-level u90),
            security-deposit: (/ (* reward-amount security-level) u100)
        })
        (var-set next-problem-id (+ problem-id u1))
        (ok problem-id)))

(define-public (submit-crowd-solution
    (problem-id uint)
    (solver-id uint)
    (solution-data (string-ascii 400))
    (implementation-proof (string-ascii 200))
    (confidence-score uint))
    (let ((problem (unwrap! (map-get? problems problem-id) err-not-found))
          (solver (unwrap! (map-get? crowd-solvers solver-id) err-not-found))
          (solution-id (var-get next-solution-id))
          (security-req (unwrap! (map-get? problem-security-requirements problem-id) err-not-found)))
        (asserts! (is-eq (get status problem) "active") err-invalid-status)
        (asserts! (< stacks-block-height (get deadline problem)) err-deadline-passed)
        (asserts! (is-eq tx-sender (get owner solver)) err-unauthorized)
        (asserts! (>= (get security-clearance solver) (get security-level problem)) err-verification-failed)
        (map-set solutions solution-id {
            problem-id: problem-id,
            solver-id: solver-id,
            solution-data: solution-data,
            implementation-proof: implementation-proof,
            confidence-score: confidence-score,
            verification-status: "pending",
            votes-received: u0,
            security-verified: false,
            submitted-at: stacks-block-height,
            reward-claimed: false
        })
        (map-set problems problem-id 
            (merge problem {solution-count: (+ (get solution-count problem) u1)}))
        (var-set next-solution-id (+ solution-id u1))
        (ok solution-id)))

(define-public (verify-solution-security
    (solution-id uint)
    (verification-score uint)
    (security-assessment uint)
    (implementation-check bool)
    (reasoning (string-ascii 200)))
    (let ((solution (unwrap! (map-get? solutions solution-id) err-not-found))
          (problem (unwrap! (map-get? problems (get problem-id solution)) err-not-found)))
        (asserts! (get verification-required problem) err-verification-failed)
        (asserts! (is-none (map-get? solution-verifications {solution-id: solution-id, verifier: tx-sender})) err-already-exists)
        (map-set solution-verifications {solution-id: solution-id, verifier: tx-sender} {
            verification-score: verification-score,
            security-assessment: security-assessment,
            implementation-check: implementation-check,
            reasoning: reasoning,
            verified-at: stacks-block-height
        })
        (let ((new-votes (+ (get votes-received solution) u1)))
            (map-set solutions solution-id 
                (merge solution {
                    votes-received: new-votes,
                    security-verified: (and (get security-verified solution) implementation-check)
                }))
            (if (>= new-votes (var-get min-verification-votes))
                (finalize-solution-verification solution-id)
                (ok true)))))

(define-public (cast-crowd-vote
    (problem-id uint)
    (preferred-solution-id uint)
    (vote-weight uint)
    (voting-reasoning (string-ascii 150)))
    (let ((problem (unwrap! (map-get? problems problem-id) err-not-found))
          (solution (unwrap! (map-get? solutions preferred-solution-id) err-not-found)))
        (asserts! (is-eq (get status problem) "active") err-invalid-status)
        (asserts! (< stacks-block-height (get deadline problem)) err-deadline-passed)
        (asserts! (<= vote-weight u100) err-invalid-amount)
        (asserts! (is-none (map-get? crowd-voting {problem-id: problem-id, voter: tx-sender})) err-already-exists)
        (map-set crowd-voting {problem-id: problem-id, voter: tx-sender} {
            preferred-solution-id: preferred-solution-id,
            vote-weight: vote-weight,
            voting-reasoning: voting-reasoning,
            cast-at: stacks-block-height
        })
        (ok true)))

(define-public (resolve-crowd-problem (problem-id uint))
    (let ((problem (unwrap! (map-get? problems problem-id) err-not-found)))
        (asserts! (is-eq (get status problem) "active") err-invalid-status)
        (asserts! (>= stacks-block-height (get deadline problem)) err-deadline-passed)
        (asserts! (or (is-eq tx-sender (get creator problem)) (is-eq tx-sender contract-owner)) err-unauthorized)
        (let ((winning-solution-id (find-best-solution problem-id)))
            (if (> winning-solution-id u0)
                (begin
                    (try! (distribute-crowd-rewards problem-id winning-solution-id))
                    (map-set problems problem-id (merge problem {status: "resolved"}))
                    (ok winning-solution-id))
                (begin
                    (try! (refund-problem-reward problem-id))
                    (map-set problems problem-id (merge problem {status: "unresolved"}))
                    (ok u0))))))

(define-public (claim-solution-reward (solution-id uint))
    (let ((solution (unwrap! (map-get? solutions solution-id) err-not-found))
          (problem (unwrap! (map-get? problems (get problem-id solution)) err-not-found))
          (solver (unwrap! (map-get? crowd-solvers (get solver-id solution)) err-not-found)))
        (asserts! (is-eq (get status problem) "resolved") err-invalid-status)
        (asserts! (not (get reward-claimed solution)) err-already-exists)
        (asserts! (is-eq tx-sender (get owner solver)) err-unauthorized)
        (asserts! (or (not (get verification-required problem)) 
                     (is-eq (get verification-status solution) "verified")) err-verification-failed)
        (map-set solutions solution-id (merge solution {reward-claimed: true}))
        (ok true)))

(define-public (update-solver-specialization
    (solver-id uint)
    (domain (string-ascii 30))
    (proficiency-level uint))
    (let ((solver (unwrap! (map-get? crowd-solvers solver-id) err-not-found)))
        (asserts! (is-eq tx-sender (get owner solver)) err-unauthorized)
        (map-set solver-specializations {solver-id: solver-id, domain: domain} {
            proficiency-level: proficiency-level,
            problems-solved-in-domain: u0,
            domain-reputation: u100,
            certification-verified: false
        })
        (ok true)))

(define-public (update-platform-settings 
    (fee uint) 
    (min-stake uint) 
    (min-votes uint) 
    (threshold uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set platform-fee fee)
        (var-set min-solver-stake min-stake)
        (var-set min-verification-votes min-votes)
        (var-set verification-threshold threshold)
        (ok true)))

(define-private (finalize-solution-verification (solution-id uint))
    (let ((solution (unwrap! (map-get? solutions solution-id) err-not-found))
          (avg-score (calculate-average-verification-score solution-id)))
        (if (>= avg-score (var-get verification-threshold))
            (map-set solutions solution-id 
                (merge solution {verification-status: "verified"}))
            (map-set solutions solution-id 
                (merge solution {verification-status: "rejected"})))
        (ok true)))

(define-private (distribute-crowd-rewards (problem-id uint) (winning-solution-id uint))
    (let ((problem (unwrap! (map-get? problems problem-id) err-not-found))
          (solution (unwrap! (map-get? solutions winning-solution-id) err-not-found))
          (solver (unwrap! (map-get? crowd-solvers (get solver-id solution)) err-not-found))
          (total-reward (get reward-amount problem))
          (platform-cut (/ (* total-reward (var-get platform-fee)) u1000))
          (solver-reward (- total-reward platform-cut)))
        (try! (as-contract (stx-transfer? solver-reward tx-sender (get owner solver))))
        (try! (as-contract (stx-transfer? platform-cut tx-sender contract-owner)))
        (try! (update-solver-stats (get solver-id solution) solver-reward))
        (ok true)))

(define-private (refund-problem-reward (problem-id uint))
    (let ((problem (unwrap! (map-get? problems problem-id) err-not-found))
          (reward-amount (get reward-amount problem)))
        (try! (as-contract (stx-transfer? reward-amount tx-sender (get creator problem))))
        (ok true)))

(define-private (find-best-solution (problem-id uint))
    (match (map-get? problems problem-id)
        problem (if (> (get solution-count problem) u0) u1 u0)
        u0))

(define-private (calculate-average-verification-score (solution-id uint))
    u85)

(define-private (update-solver-stats (solver-id uint) (reward-amount uint))
    (let ((solver (unwrap! (map-get? crowd-solvers solver-id) err-not-found)))
        (map-set crowd-solvers solver-id 
            (merge solver {
                problems-solved: (+ (get problems-solved solver) u1),
                total-rewards-earned: (+ (get total-rewards-earned solver) reward-amount),
                reputation-score: (+ (get reputation-score solver) u10),
                success-rate: (calculate-success-rate 
                    (+ (get problems-solved solver) u1)
                    (+ (get problems-solved solver) u1))
            }))
        (ok true)))

(define-private (calculate-success-rate (problems-solved uint) (total-attempts uint))
    (if (> total-attempts u0)
        (/ (* problems-solved u100) total-attempts)
        u0))

(define-read-only (get-problem (problem-id uint))
    (map-get? problems problem-id))

(define-read-only (get-solution (solution-id uint))
    (map-get? solutions solution-id))

(define-read-only (get-crowd-solver (solver-id uint))
    (map-get? crowd-solvers solver-id))

(define-read-only (get-solution-verification (solution-id uint) (verifier principal))
    (map-get? solution-verifications {solution-id: solution-id, verifier: verifier}))

(define-read-only (get-problem-security-requirements (problem-id uint))
    (map-get? problem-security-requirements problem-id))

(define-read-only (get-solver-specialization (solver-id uint) (domain (string-ascii 30)))
    (map-get? solver-specializations {solver-id: solver-id, domain: domain}))

(define-read-only (get-crowd-vote (problem-id uint) (voter principal))
    (map-get? crowd-voting {problem-id: problem-id, voter: voter}))

(define-read-only (get-platform-stats)
    {
        total-problems: (- (var-get next-problem-id) u1),
        total-solutions: (- (var-get next-solution-id) u1),
        total-solvers: (- (var-get next-solver-id) u1),
        platform-fee: (var-get platform-fee),
        min-solver-stake: (var-get min-solver-stake),
        min-verification-votes: (var-get min-verification-votes),
        verification-threshold: (var-get verification-threshold)
    })