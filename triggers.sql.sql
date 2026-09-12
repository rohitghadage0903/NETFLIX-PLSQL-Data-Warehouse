-- ============================================================================
-- 04_TRIGGERS.SQL: Audit Logging and System Maintenance
-- ============================================================================

-- Row-level trigger to sync updated_at on TITLES
CREATE OR REPLACE TRIGGER trg_titles_biu
BEFORE INSERT OR UPDATE ON titles
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        :NEW.created_at := SYSTIMESTAMP;
        :NEW.updated_at := SYSTIMESTAMP;
    ELSIF UPDATING THEN
        :NEW.updated_at := SYSTIMESTAMP;
    END IF;
END;
/

-- Audit trigger logging mutations into TITLES_AUDIT_LOG
CREATE OR REPLACE TRIGGER trg_titles_audit
AFTER INSERT OR UPDATE OR DELETE ON titles
FOR EACH ROW
DECLARE
    v_action VARCHAR2(10);
BEGIN
    IF INSERTING THEN
        v_action := 'INSERT';
        INSERT INTO titles_audit_log (
            title_id, show_id, action_type, changed_by, changed_at,
            old_title, new_title, old_rating, new_rating,
            old_duration, new_duration
        ) VALUES (
            :NEW.title_id, :NEW.show_id, v_action, USER, SYSTIMESTAMP,
            NULL, :NEW.title, NULL, :NEW.rating,
            NULL, :NEW.duration_value
        );
    ELSIF UPDATING THEN
        v_action := 'UPDATE';
        INSERT INTO titles_audit_log (
            title_id, show_id, action_type, changed_by, changed_at,
            old_title, new_title, old_rating, new_rating,
            old_duration, new_duration
        ) VALUES (
            :NEW.title_id, :NEW.show_id, v_action, USER, SYSTIMESTAMP,
            :OLD.title, :NEW.title, :OLD.rating, :NEW.rating,
            :OLD.duration_value, :NEW.duration_value
        );
    ELSIF DELETING THEN
        v_action := 'DELETE';
        INSERT INTO titles_audit_log (
            title_id, show_id, action_type, changed_by, changed_at,
            old_title, new_title, old_rating, new_rating,
            old_duration, new_duration
        ) VALUES (
            :OLD.title_id, :OLD.show_id, v_action, USER, SYSTIMESTAMP,
            :OLD.title, NULL, :OLD.rating, NULL,
            :OLD.duration_value, NULL
        );
    END IF;
END;
/