-- 1. Create tables and insert sample data
DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;

CREATE TABLE lab_sessions (
    session_id SERIAL PRIMARY KEY,
    lab_name VARCHAR(50) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id INT REFERENCES lab_sessions(session_id),
    lecturer VARCHAR(100) NOT NULL,
    workstations_reserved INT NOT NULL CHECK (workstations_reserved > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'CONFIRMED'
);

INSERT INTO lab_sessions (lab_name, available_workstations) VALUES
('Lab A - AI Lab', 30),
('Lab B - Network Lab', 2),
('Lab C - Systems Lab', 0);

-- 2. IF ELSIF ELSE check session availability
DO $$
DECLARE
    v_available INT;
    v_lab VARCHAR(50) := 'Lab B - Network Lab';
BEGIN
    SELECT available_workstations INTO v_available FROM lab_sessions WHERE lab_name = v_lab;
    
    IF v_available = 0 THEN
        RAISE NOTICE 'Session % is FULL.', v_lab;
    ELSIF v_available < 5 THEN
        RAISE NOTICE 'Session % is NEARLY FULL (% left).', v_lab, v_available;
    ELSE
        RAISE NOTICE 'Session % HAS ENOUGH WORKSTATIONS (% left).', v_lab, v_available;
    END IF;
END $$;

-- 3. WHILE loop and Numeric FOR loop
DO $$
DECLARE
    i INT := 1;
BEGIN
    RAISE NOTICE '--- Session Preparation Reminders (WHILE) ---';
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Preparation Reminder #%', i;
        i := i + 1;
    END LOOP;

    RAISE NOTICE '--- Workstation Checks (FOR) ---';
    FOR ws IN 1..3 LOOP
        RAISE NOTICE 'Checking Workstation #%', ws;
    END LOOP;
END $$;

-- 4. Create reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INT,
    p_lecturer VARCHAR,
    p_num_workstations INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_num_workstations <= 0 THEN
        RAISE EXCEPTION 'Invalid reservation amount: %', p_num_workstations;
    END IF;

    SELECT available_workstations INTO v_available FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF v_available < p_num_workstations THEN
        RAISE NOTICE 'Reservation failed: Requested %, but only % available in Session %.', 
                     p_num_workstations, v_available, p_session_id;
    ELSE
        UPDATE lab_sessions SET available_workstations = available_workstations - p_num_workstations WHERE session_id = p_session_id;
        INSERT INTO reservations (session_id, lecturer, workstations_reserved, status)
        VALUES (p_session_id, p_lecturer, p_num_workstations, 'CONFIRMED');
        RAISE NOTICE 'Reserved % workstations for % in Session %.', p_num_workstations, p_lecturer, p_session_id;
    END IF;
END $$;

-- 5. Call procedure and inspect results
CALL reserve_workstations(1, 'Dr. Smith', 10);
CALL reserve_workstations(2, 'Prof. Jones', 2);
CALL reserve_workstations(2, 'Dr. Taylor', 5); -- Exceeds capacity

SELECT * FROM lab_sessions;
SELECT * FROM reservations;

-- 6. Create cancel_reservation procedure
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_session_id INT;
    v_count INT;
BEGIN
    SELECT status, session_id, workstations_reserved INTO v_status, v_session_id, v_count 
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled. No workstations released.', p_reservation_id;
    ELSE
        UPDATE lab_sessions SET available_workstations = available_workstations + v_count WHERE session_id = v_session_id;
        UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
        RAISE NOTICE 'Reservation % cancelled. % workstations released.', p_reservation_id, v_count;
    END IF;
END $$;

-- Test double cancellation
CALL cancel_reservation(1);
CALL cancel_reservation(1);

-- 7. Explicit Cursor for low workstation availability
DO $$
DECLARE
    cur_labs CURSOR FOR 
        SELECT lab_name, available_workstations FROM lab_sessions WHERE available_workstations < 5;
    v_rec RECORD;
BEGIN
    RAISE NOTICE '--- Sessions with Few Workstations ---';
    OPEN cur_labs;
    LOOP
        FETCH cur_labs INTO v_rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Lab: %, Workstations Available: %', v_rec.lab_name, v_rec.available_workstations;
    END LOOP;
    CLOSE cur_labs;
END $$;

-- 8. Exception block for zero workstation request
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Adams', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught Exception: %', SQLERRM;
END $$;

-- 9. Query final state
SELECT * FROM lab_sessions;
SELECT * FROM reservations;