-- Extension creation for cryptographic functions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE USER_STATUS_ENUM AS ENUM ('verified', 'banned');
CREATE TYPE USER_ROLE_ENUM AS ENUM ('admin', 'buyer', 'seller');
CREATE TYPE ORDER_STATUS_ENUM AS ENUM ('pending', 'completed', 'cancelled');

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(15),
    status USER_STATUS_ENUM,
    role USER_ROLE_ENUM,
    password_hash VARCHAR(255) NOT NULL,
    admin_approved_additional_fields_record_id INT,
    CONSTRAINT chk_user_status CHECK (status IN ('verified', 'banned')),
    CONSTRAINT chk_user_role CHECK (role IN ('admin', 'buyer', 'seller'))
);

-- Log of changes for additional user fields
-- The record referenced by the user is considered the current approved version
-- created_at after the currently approved record is considered pending
-- created_at before the currently approved record without an approval date is considered outdated
-- created_at before the currently approved record but with an approval date is considered previously_approved
CREATE TABLE user_additional_fields (
    additional_fields_record_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    -- Let's consider, for simplicity, that the JSONB schema changes rarely, then it is possible to store all the additional fields together (allowing coordinated approval of changes/additions to multiple fields simultaneously).
    -- However, keep in mind that changing the structure of JSONB can be performance-intensive.
    -- If necessary, each field can be stored in a separate JSONB for improved performance during changes. 
    additional_fields_record_value JSONB,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    approved_at TIMESTAMPTZ,
    CONSTRAINT fk_admin_approved FOREIGN KEY (user_id) REFERENCES users(user_id)
);

ALTER TABLE users
ADD CONSTRAINT fk_admin_approved_additional_fields
FOREIGN KEY (admin_approved_additional_fields_record_id)
REFERENCES user_additional_fields(additional_fields_record_id);

CREATE INDEX idx_user_additional_fields_user_id ON user_additional_fields (user_id);

-- Trigger to update approved_at when admin_approved_additional_fields_record_id changes
CREATE OR REPLACE FUNCTION update_additional_fields_approved_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.admin_approved_additional_fields_record_id IS NOT NULL THEN
        UPDATE user_additional_fields
        SET approved_at = CURRENT_TIMESTAMP
        WHERE additional_fields_record_id = NEW.admin_approved_additional_fields_record_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_additional_fields_approved_at_trigger
AFTER UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_additional_fields_approved_at();

-- A separate table for units of measurement allows writing migration scripts that change the unit of measurement and recalculate the quantity of goods in orders. It also helps return options to the front-end for Select/Autocomplete when creating a product.
CREATE TABLE units_of_measurement (
    unit_id SERIAL PRIMARY KEY,
    unit_name VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    impa_code VARCHAR(6) UNIQUE NOT NULL CHECK (impa_code ~ '^\d{6}$'),
    name VARCHAR(255) NOT NULL,
    unit_of_measurement_id INT REFERENCES units_of_measurement(unit_id) NOT NULL
);

CREATE TABLE user_folders (
    folder_id SERIAL PRIMARY KEY,
    buyer_id INT REFERENCES users(user_id) NOT NULL,
    folder_name VARCHAR(255) NOT NULL
);

CREATE OR REPLACE FUNCTION check_user_role_buyer()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.buyer_id IS NOT NULL THEN
        IF (SELECT role FROM users WHERE user_id = NEW.buyer_id) != 'buyer' THEN
            RAISE EXCEPTION 'ERR_USER_NOT_BUYER';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_user_role_seller()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.seller_id IS NOT NULL THEN
        IF (SELECT role FROM users WHERE user_id = NEW.seller_id) != 'seller' THEN
            RAISE EXCEPTION 'ERR_USER_NOT_SELLER';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to check user role before inserting into user_folders
CREATE TRIGGER check_user_role_trigger_user_folders
BEFORE INSERT ON user_folders
FOR EACH ROW
EXECUTE FUNCTION check_user_role_buyer();

CREATE INDEX idx_user_folders_buyer_id ON user_folders (buyer_id);

-- Table for products in user folders
CREATE TABLE user_folder_items (
    folder_item_id SERIAL PRIMARY KEY,
    folder_id INT REFERENCES user_folders(folder_id) NOT NULL,
    product_id INT REFERENCES products(product_id) NOT NULL
);

CREATE TABLE ports (
    port_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    locode VARCHAR(10) UNIQUE NOT NULL
);

CREATE TABLE ships (
    ship_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    imo VARCHAR(20) UNIQUE NOT NULL,
    buyer_id INT REFERENCES users(user_id)
);

-- Trigger for user role check before inserting into ships table
CREATE TRIGGER check_user_role_trigger_ships
BEFORE INSERT ON ships
FOR EACH ROW
EXECUTE FUNCTION check_user_role_buyer();

-- Table for linking users to ports they work with
CREATE TABLE user_ports (
    user_id INT REFERENCES users(user_id),
    port_id INT REFERENCES ports(port_id),
    PRIMARY KEY (user_id, port_id)
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    buyer_id INT REFERENCES users(user_id) NOT NULL,
    status ORDER_STATUS_ENUM DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Trigger to check user role before inserting into orders
CREATE TRIGGER check_user_role_trigger_orders
BEFORE INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION check_user_role_buyer();

CREATE INDEX idx_orders_buyer_id ON orders (buyer_id);

-- Table for ports in an order
CREATE TABLE order_ports (
    order_id INT REFERENCES orders(order_id) NOT NULL,
    port_id INT REFERENCES ports(port_id) NOT NULL,
    PRIMARY KEY (order_id, port_id)
);

-- Table for products in an order
CREATE TABLE order_items (
    order_id INT REFERENCES orders(order_id) NOT NULL,
    product_id INT REFERENCES products(product_id) NOT NULL,
    quantity INT NOT NULL,
    PRIMARY KEY (order_id, product_id)
);

-- Table for seller responses to an order
CREATE TABLE order_responses (
    response_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(order_id) NOT NULL,
    seller_id INT REFERENCES users(user_id) NOT NULL,
    buyer_id INT REFERENCES users(user_id) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Triggers for checking user role before inserting seller response
CREATE TRIGGER check_user_role_seller_response_trigger
BEFORE INSERT ON order_responses
FOR EACH ROW
EXECUTE FUNCTION check_user_role_seller();

CREATE TRIGGER check_user_role_buyer_response_trigger
BEFORE INSERT ON order_responses
FOR EACH ROW
EXECUTE FUNCTION check_user_role_buyer();

-- Table for changes in item list in response
CREATE TABLE response_items (
    response_item_id SERIAL PRIMARY KEY,
    response_id INT REFERENCES order_responses(response_id) NOT NULL,
    product_id INT REFERENCES products(product_id) NOT NULL,
    suggested_quantity INT NOT NULL
);

-- Table for chat related to an order
CREATE TABLE order_chat (
    message_id SERIAL PRIMARY KEY,
    response_id INT REFERENCES order_responses(response_id),
    sender_id INT REFERENCES users(user_id),
    message_text VARCHAR(1000) NOT NULL,
    sent_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    viewed_at TIMESTAMPTZ
);

CREATE TABLE tariffs (
    tariff_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    max_orders_per_month INT,
    price_in_cents INT,
    billing_period_in_months INT
);

-- Table linking buyer to tariff with billing information
CREATE TABLE buyer_tariff (
    buyer_id INT REFERENCES users(user_id),
    tariff_id INT REFERENCES tariffs(tariff_id),
    billing_start_date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (buyer_id, tariff_id)
);

CREATE INDEX idx_buyer_tariff_buyer_id ON buyer_tariff(buyer_id);

-- Trigger for checking user role before inserting buyer's tariff
CREATE TRIGGER check_user_role_buyer_tariff_trigger
BEFORE INSERT ON buyer_tariff 
FOR EACH ROW
EXECUTE FUNCTION check_user_role_buyer();

-- Trigger to limit the number of orders per month
-- Orders are replenished after 1 month passes
-- Billing implementation based on monthly periods starting from the tariff purchase date
CREATE OR REPLACE FUNCTION enforce_order_limit()
RETURNS TRIGGER AS $$
DECLARE
    ERR_NO_ACTIVE_TARIFF CONSTANT TEXT := 'ERR_NO_ACTIVE_TARIFF';
    ERR_ORDER_PER_MONTH_LIMIT_REACHED CONSTANT TEXT := 'ERR_ORDER_PER_MONTH_LIMIT_REACHED';
    
    current_billing_period_start_date TIMESTAMPTZ;
    current_billing_period_end_date TIMESTAMPTZ;

    buyer_tariff_record RECORD;
BEGIN
    -- Get the buyer's tariff record
    SELECT * INTO buyer_tariff_record
    FROM buyer_tariff
    WHERE buyer_id = NEW.buyer_id;

    IF buyer_tariff_record.buyer_id IS NOT NULL THEN
        -- Determine the start of the current billing period starting from billing_start_date in the buyer's tariff
        current_billing_period_start_date := buyer_tariff_record.billing_start_date;

        -- add full months until reaching the start date of the current period
        WHILE CURRENT_TIMESTAMP - current_billing_period_start_date > INTERVAL '1 month' 
        LOOP
            current_billing_period_start_date := current_billing_period_start_date + INTERVAL '1 month';
        END LOOP;

        -- Calculate the end date of the billing period
        current_billing_period_end_date := current_billing_period_start_date + INTERVAL '1 month';

        -- Check the number of orders for the current user and tariff
        IF (
                -- The number of orders created during the current billing period
                (
                    SELECT COUNT(*)
                    FROM orders
                    WHERE buyer_id = NEW.buyer_id
                    AND created_at >= current_billing_period_start_date 
                    AND created_at < current_billing_period_end_date 
                ) > 
                -- The maximum allowed number of orders according to the tariff
                (
                    SELECT max_orders_per_month
                    FROM tariffs
                    WHERE tariff_id = buyer_tariff_record.tariff_id
                )
        ) THEN
            RAISE EXCEPTION '%', ERR_ORDER_PER_MONTH_LIMIT_REACHED;
        END IF;
    ELSE
        RAISE EXCEPTION '%', ERR_NO_ACTIVE_TARIFF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to limit the number of orders per month
CREATE TRIGGER enforce_order_limit_trigger
BEFORE INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION enforce_order_limit();

-----------------------------------------------------------------------
---------------------------   TEST DATA   -----------------------------
-----------------------------------------------------------------------

INSERT INTO users (email, name, phone, status, role, password_hash)
VALUES 
  ('user1@example.com', 'User One', '123456789', 'verified', 'buyer', crypt('password123', gen_salt('bf'))),
  ('user2@example.com', 'User Two', '987654321', 'verified', 'seller', crypt('password456', gen_salt('bf'))),
  ('user3@example.com', 'User Three', NULL, 'verified', 'admin', crypt('adminpass', gen_salt('bf')));

-- Example addition of an "SSN" additional field for user with user_id = 1
WITH new_fields AS (
    INSERT INTO user_additional_fields (user_id, additional_fields_record_value)
    VALUES (1, '{"ssn": "123456789"}')
    RETURNING additional_fields_record_id
)
-- Approve the created record with additional fields
UPDATE users
SET admin_approved_additional_fields_record_id = (SELECT additional_fields_record_id FROM new_fields)
WHERE user_id = 1;

-- An example of adding an additional field 'avatar_url' for a user after approving the previous set of fields
INSERT INTO user_additional_fields (user_id, additional_fields_record_value)
VALUES (1, '{"ssn": "123456789", "avatar_url": "https://example.com/avatar.jpg"}');

INSERT INTO ports (name, locode)
VALUES 
  ('Port A', 'LOCODE1'),
  ('Port B', 'LOCODE2'),
  ('Port C', 'LOCODE3');

INSERT INTO ships (name, imo, buyer_id)
VALUES 
  ('Ship One', 'IMO111', 1),
  ('Ship Two', 'IMO222', 1);

INSERT INTO user_ports (user_id, port_id)
VALUES 
  (1, 1),
  (2, 2),
  (2, 3);

INSERT INTO units_of_measurement (unit_name)
VALUES 
  ('BARREL'),
  ('KG'),
  ('LITER');

INSERT INTO products (impa_code, name, unit_of_measurement_id)
VALUES 
  ('123456', 'Product One', 1),
  ('654321', 'Product Two', 2),
  ('987654', 'Product Three', 3);

INSERT INTO tariffs (name, max_orders_per_month, price_in_cents, billing_period_in_months)
VALUES 
  ('Basic', 3, 5000, 1),
  ('Premium', 4, 10000, 1),
  ('Business', 10, 15000, 12);

INSERT INTO buyer_tariff (buyer_id, tariff_id, billing_start_date)
VALUES 
  (1, 2, CURRENT_TIMESTAMP - INTERVAL '14 days');

INSERT INTO orders (buyer_id, status, created_at)
VALUES 
  (1, 'pending', CURRENT_TIMESTAMP),
  (1, 'pending', CURRENT_TIMESTAMP),
  (1, 'pending', CURRENT_TIMESTAMP),
  (1, 'completed', CURRENT_TIMESTAMP - INTERVAL '2 days'),
  (1, 'pending', CURRENT_TIMESTAMP - INTERVAL '2 month');

INSERT INTO order_ports (order_id, port_id)
VALUES 
  (1, 1),
  (1, 2),
  (2, 3),
  (3, 1);

INSERT INTO order_items (order_id, product_id, quantity)
VALUES 
  (1, 1, 100),
  (1, 2, 50),
  (2, 3, 10),
  (3, 1, 200);

INSERT INTO order_responses (order_id, seller_id, buyer_id, created_at)
VALUES 
  (1, 2, 1, CURRENT_TIMESTAMP),
  (2, 2, 1, CURRENT_TIMESTAMP - INTERVAL '1 day');

INSERT INTO response_items (response_id, product_id, suggested_quantity)
VALUES 
  (1, 1, 120),
  (1, 2, 60),
  (2, 3, 15);

INSERT INTO order_chat (response_id, sender_id, message_text, sent_at)
VALUES 
  (1, 2, 'We need seven parallel red lines, one of them is green, and another one is transparent.', CURRENT_TIMESTAMP - INTERVAL '2 hours'),
  (1, 1, 'What about the order?', CURRENT_TIMESTAMP - INTERVAL '1 hour'),
  (1, 2, 'Working on it.', CURRENT_TIMESTAMP - INTERVAL '30 minutes');
 
