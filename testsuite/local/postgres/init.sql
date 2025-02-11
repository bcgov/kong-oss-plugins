CREATE ROLE konguser WITH LOGIN PASSWORD 'konguser';
CREATE DATABASE kong OWNER konguser;

CREATE ROLE keycloakuser WITH LOGIN PASSWORD 'keycloakuser';
CREATE DATABASE keycloak OWNER keycloakuser;