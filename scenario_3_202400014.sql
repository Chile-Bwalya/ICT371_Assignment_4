-- 1. Create tables and insert sample data
DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;

CREATE TABLE hostel_rooms (
    room_id SERIAL PRIMARY KEY,
    room_number VARCHAR(20) NOT NULL UNIQUE, -- VARCHAR(20) avoids string truncation errors
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    room_id INT REFERENCES hostel_rooms(room_id),
    student_number VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
);

INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
('Block A-101', 3),
('Block A-102', 1),
('Block A-103', 0);

-- 2. IF ELSIF ELSE check room status
DO $$
DECLARE
    v_spaces INT;
    v_room VARCHAR(20) := 'Block A-102'; -- Expanded variable length to match room_number
BEGIN
    SELECT available_spaces INTO v_spaces FROM hostel_rooms WHERE room_number = v_room;
    
    IF v_spaces = 0 THEN
        RAISE NOTICE 'Room % is FULL.', v_room;
    ELSIF v_spaces = 1 THEN
        RAISE NOTICE 'Room % HAS ONE SPACE LEFT.', v_room;
    ELSE
        RAISE NOTICE 'Room % HAS SEVERAL SPACES (% left).', v_room, v_spaces;
    END IF;
END $$;

-- 3. WHILE loop and Numeric FOR loop
DO $$
DECLARE
    day_count INT := 1;
BEGIN
    RAISE NOTICE '--- Inspection Days (WHILE) ---';
    WHILE day_count <= 3 LOOP
        RAISE NOTICE 'Hostel Inspection Day #%', day_count;
        day_count := day_count + 1;
    END LOOP;

    RAISE NOTICE '--- Room Checks (FOR) ---';
    FOR room_check IN 1..3 LOOP
        RAISE NOTICE 'Checking Room #%', room_check;
    END LOOP; -- Corrected PL/pgSQL loop termination syntax
END $$;

-- 4. Create allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(
    p_room_id INT,
    p_student_number VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INT;
BEGIN
    -- Validate blank/whitespace-only student numbers
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Student number cannot be blank.';
    END IF;

    SELECT available_spaces INTO v_spaces FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF v_spaces IS NULL THEN
        RAISE NOTICE 'Allocation failed: Room ID % does not exist.', p_room_id;
    ELSIF v_spaces <= 0 THEN
        RAISE NOTICE 'Allocation failed: Room ID % is completely full.', p_room_id;
    ELSE
        UPDATE hostel_rooms SET available_spaces = available_spaces - 1 WHERE room_id = p_room_id;
        INSERT INTO allocations (room_id, student_number, status)
        VALUES (p_room_id, p_student_number, 'ALLOCATED');
        RAISE NOTICE 'Allocated 1 bed space in Room ID % to student %.', p_room_id, p_student_number;
    END IF;
END $$;

-- 5. Call allocate_room for 2 valid allocations and 1 full room request
CALL allocate_room(1, '202400014');
CALL allocate_room(2, '202400015');
CALL allocate_room(3, '202400016'); -- Room 3 is full (available_spaces = 0)

-- Query tables after attempts
SELECT * FROM hostel_rooms;
SELECT * FROM allocations;

-- 6. Create check_out procedure (Idempotent: prevents duplicate releases)
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_room_id INT;
BEGIN
    SELECT status, room_id INTO v_status, v_room_id 
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE NOTICE 'Check-out failed: Allocation ID % not found.', p_allocation_id;
    ELSIF v_status = 'COMPLETED' THEN
        RAISE NOTICE 'Allocation ID % is already completed. Space not freed again.', p_allocation_id;
    ELSE
        UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room_id;
        UPDATE allocations SET status = 'COMPLETED' WHERE allocation_id = p_allocation_id;
        RAISE NOTICE 'Check-out successful for Allocation ID %. Bed space restored.', p_allocation_id;
    END IF;
END $$;

-- Test double check-out on the same allocation ID
CALL check_out(1);
CALL check_out(1); -- Second call correctly alerts without incrementing room spaces again

-- 7. Explicit Cursor for full or nearly full rooms
DO $$
DECLARE
    cur_rooms CURSOR FOR 
        SELECT room_number, available_spaces FROM hostel_rooms WHERE available_spaces <= 1;
    v_rec RECORD;
BEGIN
    RAISE NOTICE '--- Full or Nearly Full Rooms ---';
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Room: %, Available Spaces: %', v_rec.room_number, v_rec.available_spaces;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- 8. Handle invalid input (blank student number) with EXCEPTION block
DO $$
BEGIN
    CALL allocate_room(1, '   '); -- Triggers exception
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught Exception: %', SQLERRM;
END $$;

-- 9. Query both tables to show final available spaces and allocation statuses
SELECT * FROM hostel_rooms;
SELECT * FROM allocations;