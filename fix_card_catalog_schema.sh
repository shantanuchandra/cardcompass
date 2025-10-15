#!/bin/bash
# Script to apply card catalog schema standardization and verify the fix

# Display banner
echo "================================================"
echo "CardCompass - Card Catalog Schema Standardization"
echo "================================================"
echo

# Detect database connection parameters
if [ -f .env ]; then
  echo "Loading database parameters from .env file..."
  source .env
  DB_USER=${POSTGRES_USER:-postgres}
  DB_NAME=${POSTGRES_DB:-cardcompass}
  DB_HOST=${POSTGRES_HOST:-localhost}
  DB_PORT=${POSTGRES_PORT:-5432}
else
  echo "No .env file found, using default database parameters..."
  DB_USER=postgres
  DB_NAME=cardcompass
  DB_HOST=localhost
  DB_PORT=5432
fi

echo "Using database: $DB_NAME on $DB_HOST:$DB_PORT"
echo

# Function to check if psql is available
check_psql() {
  if ! command -v psql &> /dev/null; then
    echo "Error: PostgreSQL client (psql) not found."
    echo "Please install PostgreSQL client tools and try again."
    exit 1
  fi
}

# Function to execute SQL and capture output
execute_sql() {
  local sql_file=$1
  echo "Executing $sql_file..."
  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f $sql_file
  if [ $? -ne 0 ]; then
    echo "Error executing $sql_file. Please check the SQL syntax and database connection."
    exit 1
  fi
  echo "Successfully executed $sql_file"
  echo
}

# Function to check schema state
check_schema() {
  echo "Checking card_catalog schema state..."
  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "
  SELECT 
    column_name, 
    data_type, 
    is_nullable
  FROM 
    information_schema.columns 
  WHERE 
    table_name = 'card_catalog'
  ORDER BY 
    ordinal_position;"
  
  echo
  echo "Checking for any 'is_active' columns in card_catalog..."
  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns 
    WHERE table_name = 'card_catalog' AND column_name = 'is_active'
  ) AS is_active_exists;"
  
  echo
  echo "Checking for 'is_discontinued' column in card_catalog..."
  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns 
    WHERE table_name = 'card_catalog' AND column_name = 'is_discontinued'
  ) AS is_discontinued_exists;"
}

# Main execution
check_psql

echo "Step 1: Check current schema state"
check_schema

echo "Step 2: Apply schema standardization"
execute_sql "standardize_card_catalog_schema.sql"

echo "Step 3: Verify schema state after fix"
check_schema

echo
echo "Schema standardization process completed!"
echo "If you still encounter errors in the application, please check the debug logs for more details."
echo
