-- Create the database if it doesn't exist, then connect to it and create schemas
-- This file is executed by psql during container init without requiring execute permissions

-- Create the database if missing (uses \\gexec to run the generated CREATE statement)
SELECT 'CREATE DATABASE db_project'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'db_project');
\gexec

-- Connect to the new database and create schemas there
\connect db_project

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS staging;

-- Done


SELECT 'CREATE DATABASE transactional_db'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'transactional_db');
\gexec

-- Connect to the new database and create schemas there
\connect transactional_db
CREATE SCHEMA IF NOT EXISTS production;


-- ddl
-- 1. Create the schema

-- 2. Vendors table (Dimension)
CREATE TABLE production.vendors (
    vendor_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    base_price DECIMAL(10, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Bookings table (Fact)
CREATE TABLE production.bookings (
    booking_id SERIAL PRIMARY KEY,
    vendor_id INT REFERENCES production.vendors(vendor_id),
    status VARCHAR(50) DEFAULT 'pending',
    total_amount DECIMAL(10, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Seed with initial data
INSERT INTO production.vendors (name, category, base_price) VALUES 
('Vivid Photos', 'Photography', 2500.00),
('Gourmet Catering', 'Catering', 5000.00);

INSERT INTO production.bookings (vendor_id, total_amount) VALUES (1, 2500.00);



CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_bookings_modtime
    BEFORE UPDATE ON production.bookings
    FOR EACH ROW
    EXECUTE PROCEDURE update_updated_at_column();
