-- Self-test fixture: a routine, safe migration.
CREATE TABLE users (
  id BIGINT PRIMARY KEY,
  email TEXT NOT NULL
);
