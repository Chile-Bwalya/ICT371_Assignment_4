-- 1. Create tables and insert sample data
DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;

CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id SERIAL PRIMARY KEY,
    book_id INT REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'ISSUED'
);

INSERT INTO books (title, available_copies) VALUES
('Database Systems Concepts', 5),
('Introduction to Algorithms', 1),
('Clean Code', 0);

-- 2. IF ELSIF ELSE check stock status
DO $$
DECLARE
    v_copies INT;
    v_title VARCHAR(100) := 'Database Systems Concepts';
BEGIN
    SELECT available_copies INTO v_copies FROM books WHERE title = v_title;
    
    IF v_copies = 0 THEN
        RAISE NOTICE 'Book "%" is unavailable.', v_title;
    ELSIF v_copies < 3 THEN
        RAISE NOTICE 'Book "%" is low on copies (Copies: %).', v_title, v_copies;
    ELSE
        RAISE NOTICE 'Book "%" is sufficiently stocked (Copies: %).', v_title, v_copies;
    END IF;
END $$;

-- 3. WHILE loop and Numeric FOR loop
DO $$
DECLARE
    i INT := 1;
BEGIN
    RAISE NOTICE '--- Overdue Reminders (WHILE) ---';
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Overdue Reminder #%', i;
        i := i + 1;
    END LOOP;

    RAISE NOTICE '--- Shelf Numbers (FOR) ---';
    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library Shelf #%', shelf;
    END LOOP;
END $$;

-- 4. Create borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id INT,
    p_student_number VARCHAR,
    p_quantity INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid loan quantity: %', p_quantity;
    END IF;

    SELECT available_copies INTO v_available FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF v_available IS NULL THEN
        RAISE EXCEPTION 'Book ID % does not exist.', p_book_id;
    ELSIF v_available < p_quantity THEN
        RAISE NOTICE 'Loan failed: Requested % copies, but only % available for Book ID %.', p_quantity, v_available, p_book_id;
    ELSE
        UPDATE books SET available_copies = available_copies - p_quantity WHERE book_id = p_book_id;
        INSERT INTO book_loans (book_id, student_number, quantity, status)
        VALUES (p_book_id, p_student_number, p_quantity, 'ISSUED');
        RAISE NOTICE 'Successfully borrowed % copies of Book ID % for student %.', p_quantity, p_book_id, p_student_number;
    END IF;
END $$;

-- 5. Call borrow_book with 2 valid requests and 1 exceeding capacity
CALL borrow_book(1, '20230001', 2); -- Valid
CALL borrow_book(2, '20230002', 1); -- Valid
CALL borrow_book(2, '20230003', 2); -- Exceeds stock (Fails gracefully)

SELECT * FROM books;
SELECT * FROM book_loans;

-- 6. Create return_book procedure (Idempotent: handles double calls)
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_book_id INT;
    v_qty INT;
BEGIN
    SELECT status, book_id, quantity INTO v_status, v_book_id, v_qty 
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE NOTICE 'Loan ID % not found.', p_loan_id;
    ELSIF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan ID % is already returned. No copies added.', p_loan_id;
    ELSE
        UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;
        UPDATE book_loans SET status = 'RETURNED' WHERE loan_id = p_loan_id;
        RAISE NOTICE 'Loan ID % returned successfully. % copies restored.', p_loan_id, v_qty;
    END IF;
END $$;

-- Test double return
CALL return_book(1);
CALL return_book(1); -- Second call does not restore copies again

-- 7. Explicit cursor for low stock books
DO $$
DECLARE
    cur_low_stock CURSOR FOR 
        SELECT title, available_copies FROM books WHERE available_copies < 3;
    v_rec RECORD;
BEGIN
    RAISE NOTICE '--- Books Low on Stock ---';
    OPEN cur_low_stock;
    LOOP
        FETCH cur_low_stock INTO v_rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Title: %, Copies Remaining: %', v_rec.title, v_rec.available_copies;
    END LOOP;
    CLOSE cur_low_stock;
END $$;

-- 8. Exception Handling for invalid quantity
DO $$
BEGIN
    CALL borrow_book(1, '20230004', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught Error: %', SQLERRM;
END $$;

-- 9. Final Query
SELECT * FROM books;
SELECT * FROM book_loans;