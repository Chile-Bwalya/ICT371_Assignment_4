-- 1. Create tables and insert sample data
DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;

CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id SERIAL PRIMARY KEY,
    medicine_id INT REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
('Paracetamol', 100),
('Amoxicillin', 5),
('Ibuprofen', 0);

-- 2. IF ELSIF ELSE check stock levels
DO $$
DECLARE
    v_stock INT;
    v_med VARCHAR(100) := 'Amoxicillin';
BEGIN
    SELECT stock_quantity INTO v_stock FROM medicines WHERE medicine_name = v_med;
    
    IF v_stock = 0 THEN
        RAISE NOTICE 'Medicine % is OUT OF STOCK.', v_med;
    ELSIF v_stock < 10 THEN
        RAISE NOTICE 'Medicine % is LOW ON STOCK (% units remaining).', v_med, v_stock;
    ELSE
        RAISE NOTICE 'Medicine % is SUFFICIENTLY STOCKED (% units remaining).', v_med, v_stock;
    END IF;
END $$;

-- 3. WHILE loop and Numeric FOR loop
DO $$
DECLARE
    review_day INT := 1;
BEGIN
    RAISE NOTICE '--- Stock Review Days (WHILE) ---';
    WHILE review_day <= 3 LOOP
        RAISE NOTICE 'Stock Review Day #%', review_day;
        review_day := review_day + 1;
    END LOOP;

    RAISE NOTICE '--- Shelf Inspections (FOR) ---';
    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Inspecting Medicine Shelf #%', shelf;
    END LOOP; -- Corrected syntax from END FOR to END LOOP
END $$;

-- 4. Create dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_medicine_id INT,
    p_student_number VARCHAR,
    p_quantity INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    -- Handle negative or zero quantities
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: %. Quantity must be positive.', p_quantity;
    END IF;

    SELECT stock_quantity INTO v_stock FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF v_stock IS NULL THEN
        RAISE NOTICE 'Dispensing failed: Medicine ID % does not exist.', p_medicine_id;
    ELSIF v_stock < p_quantity THEN
        RAISE NOTICE 'Dispensing failed: Requested % units, but stock is only % for Medicine ID %.', 
                     p_quantity, v_stock, p_medicine_id;
    ELSE
        UPDATE medicines SET stock_quantity = stock_quantity - p_quantity WHERE medicine_id = p_medicine_id;
        INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
        VALUES (p_medicine_id, p_student_number, p_quantity, 'DISPENSED');
        RAISE NOTICE 'Dispensed % units of Medicine ID % to student %.', p_quantity, p_medicine_id, p_student_number;
    END IF;
END $$;

-- 5. Call dispense_medicine for 2 valid requests and 1 exceeding stock
CALL dispense_medicine(1, '202400014', 10);
CALL dispense_medicine(2, '202400015', 3);
CALL dispense_medicine(2, '202400016', 10); -- Exceeds available stock

-- Query tables after attempts
SELECT * FROM medicines;
SELECT * FROM dispensing_records;

-- 6. Create reverse_dispensing procedure (Idempotent: prevents duplicate stock additions)
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_med_id INT;
    v_qty INT;
BEGIN
    SELECT status, medicine_id, quantity INTO v_status, v_med_id, v_qty 
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE NOTICE 'Reversal failed: Dispensing Record ID % not found.', p_record_id;
    ELSIF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Dispensing Record ID % is already reversed. Stock not modified again.', p_record_id;
    ELSE
        UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_med_id;
        UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
        RAISE NOTICE 'Dispensing Record ID % reversed. % units restored to stock.', p_record_id, v_qty;
    END IF;
END $$;

-- Test double reversal on the same record
CALL reverse_dispensing(1);
CALL reverse_dispensing(1); -- Second call alerts without restoring stock again

-- 7. Explicit Cursor for medicines below low-stock threshold (< 10)
DO $$
DECLARE
    cur_low_stock CURSOR FOR 
        SELECT medicine_name, stock_quantity FROM medicines WHERE stock_quantity < 10;
    v_rec RECORD;
BEGIN
    RAISE NOTICE '--- Low Stock Medicines ---';
    OPEN cur_low_stock;
    LOOP
        FETCH cur_low_stock INTO v_rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Medicine: %, Stock Remaining: %', v_rec.medicine_name, v_rec.stock_quantity;
    END LOOP;
    CLOSE cur_low_stock;
END $$;

-- 8. Request negative dispensing quantity and handle invalid input with EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, '202400014', -5); -- Triggers exception
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught Exception: %', SQLERRM;
END $$;

-- 9. Query both tables to show final stock and dispensing statuses
SELECT * FROM medicines;
SELECT * FROM dispensing_records;