-- Create the databases
CREATE DATABASE IF NOT EXISTS source_db;
CREATE DATABASE IF NOT EXISTS inventory_db;

-- Use the source database for the main tables
USE source_db;

-- 1. Vendors table (Dimension)
CREATE TABLE IF NOT EXISTS vendors (
    vendor_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    base_price DECIMAL(10, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 2. Bookings table (Fact)
CREATE TABLE IF NOT EXISTS bookings (
    booking_id INT AUTO_INCREMENT PRIMARY KEY,
    vendor_id INT,
    status VARCHAR(50) DEFAULT 'pending',
    total_amount DECIMAL(10, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_vendor FOREIGN KEY (vendor_id) REFERENCES vendors(vendor_id)
);

-- 3. Seed with initial data
INSERT INTO vendors (name, category, base_price) VALUES 
('Vivid Photos', 'Photography', 2500.00),
('Gourmet Catering', 'Catering', 5000.00);

INSERT INTO bookings (vendor_id, total_amount) VALUES (1, 2500.00);

-- Note: MySQL handles "updated_at" automatically with the 
-- ON UPDATE CURRENT_TIMESTAMP clause, so no custom function/trigger needed like in Postgres.