CREATE DATABASE IF NOT EXISTS nama_puducherry CHARACTER SET utf8mb4;
USE nama_puducherry;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  phone VARCHAR(15) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('customer','driver') NOT NULL,
  api_token CHAR(64) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_phone_role (phone, role),
  KEY idx_token (api_token)
);

CREATE TABLE IF NOT EXISTS drivers (
  user_id INT PRIMARY KEY,
  vehicle_type ENUM('auto','hatchback','sedan','suv') NOT NULL,
  vehicle_number VARCHAR(20) NOT NULL,
  license_number VARCHAR(30) NOT NULL,
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  is_online TINYINT(1) NOT NULL DEFAULT 0,
  lat DOUBLE NULL,
  lng DOUBLE NULL,
  location_updated_at DATETIME NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS rides (
  id INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  driver_id INT NULL,
  vehicle_type ENUM('auto','hatchback','sedan','suv') NOT NULL,
  pickup_lat DOUBLE NOT NULL, pickup_lng DOUBLE NOT NULL, pickup_address VARCHAR(255),
  drop_lat DOUBLE NOT NULL, drop_lng DOUBLE NOT NULL, drop_address VARCHAR(255),
  distance_km DOUBLE NOT NULL,
  fare DECIMAL(10,2) NOT NULL,
  discount DECIMAL(10,2) NOT NULL DEFAULT 0,
  offer_code VARCHAR(20) NULL,
  status ENUM('requested','accepted','arrived','started','completed','cancelled') NOT NULL DEFAULT 'requested',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_status (status),
  FOREIGN KEY (customer_id) REFERENCES users(id),
  FOREIGN KEY (driver_id) REFERENCES users(id)
);

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
