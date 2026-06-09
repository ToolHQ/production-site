-- T-362a: pgcrypto helpers (SECURITY DEFINER — n8n_app only)

SET search_path TO email_intel, public;

CREATE OR REPLACE FUNCTION encrypt_pii(plain text)
RETURNS bytea
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = email_intel, public
AS $$
BEGIN
  IF plain IS NULL OR plain = '' THEN
    RETURN NULL;
  END IF;
  RETURN pgp_sym_encrypt(plain, current_setting('app.pgcrypto_key', true));
END;
$$;

CREATE OR REPLACE FUNCTION decrypt_pii(cipher bytea)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = email_intel, public
AS $$
BEGIN
  IF cipher IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN pgp_sym_decrypt(cipher, current_setting('app.pgcrypto_key', true));
END;
$$;

REVOKE ALL ON FUNCTION encrypt_pii(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION decrypt_pii(bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION encrypt_pii(text) TO n8n_app;
GRANT EXECUTE ON FUNCTION decrypt_pii(bytea) TO n8n_app;
