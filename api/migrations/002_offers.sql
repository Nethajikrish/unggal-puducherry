USE nama_puducherry;

CREATE TABLE IF NOT EXISTS offers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(100) NOT NULL,
  description VARCHAR(255) NULL,
  audience ENUM('customer','driver','both') NOT NULL DEFAULT 'customer',
  code VARCHAR(20) NULL,
  discount_type ENUM('percent','flat') NULL,
  discount_value DECIMAL(10,2) NULL,
  max_discount DECIMAL(10,2) NULL,
  min_fare DECIMAL(10,2) NOT NULL DEFAULT 0,
  valid_from DATE NULL,
  valid_to DATE NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_code (code)
);

ALTER TABLE rides
  ADD COLUMN discount DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER fare,
  ADD COLUMN offer_code VARCHAR(20) NULL AFTER discount;
