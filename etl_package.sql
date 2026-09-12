-- ============================================================================
-- 02_ETL_PACKAGE.SQL (FIXED)
-- ============================================================================

CREATE OR REPLACE PACKAGE pkg_netflix_etl AS
    -- Exposed so the SQL engine can execute it
    FUNCTION parse_date_added(p_raw_date IN VARCHAR2) RETURN DATE;

    PROCEDURE log_error(
        p_batch_id      IN VARCHAR2,
        p_module_name   IN VARCHAR2,
        p_source_record IN VARCHAR2,
        p_error_code    IN NUMBER,
        p_error_msg     IN VARCHAR2,
        p_stack_trace   IN VARCHAR2
    );

    PROCEDURE process_staging_to_normalized(
        p_batch_id IN VARCHAR2 DEFAULT SYS_GUID()
    );
END pkg_netflix_etl;
/

CREATE OR REPLACE PACKAGE BODY pkg_netflix_etl AS

    PROCEDURE log_error(
        p_batch_id      IN VARCHAR2,
        p_module_name   IN VARCHAR2,
        p_source_record IN VARCHAR2,
        p_error_code    IN NUMBER,
        p_error_msg     IN VARCHAR2,
        p_stack_trace   IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO etl_error_log (
            batch_id, module_name, source_record, error_code, error_msg, stack_trace
        ) VALUES (
            p_batch_id, p_module_name, SUBSTR(p_source_record, 1, 500), 
            p_error_code, SUBSTR(p_error_msg, 1, 4000), SUBSTR(p_stack_trace, 1, 4000)
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END log_error;

    FUNCTION parse_date_added(p_raw_date IN VARCHAR2) RETURN DATE IS
        v_trimmed VARCHAR2(50);
    BEGIN
        IF p_raw_date IS NULL THEN
            RETURN NULL;
        END IF;
        v_trimmed := TRIM(p_raw_date);
        BEGIN
            RETURN TO_DATE(v_trimmed, 'Month DD, YYYY');
        EXCEPTION
            WHEN OTHERS THEN
                BEGIN
                    RETURN TO_DATE(v_trimmed, 'FMMonth DD, YYYY');
                EXCEPTION
                    WHEN OTHERS THEN
                        RETURN NULL;
                END;
        END;
    END parse_date_added;

    PROCEDURE process_staging_to_normalized(
        p_batch_id IN VARCHAR2 DEFAULT SYS_GUID()
    ) IS
        c_module CONSTANT VARCHAR2(50) := 'PKG_NETFLIX_ETL.PROCESS_STAGING';
        v_parsed_date DATE;
    BEGIN
        -- 1. Types
        MERGE INTO types tgt
        USING (
            SELECT DISTINCT TRIM(type) AS type_name
            FROM netflix_staging
            WHERE type IS NOT NULL
        ) src
        ON (tgt.type_name = src.type_name)
        WHEN NOT MATCHED THEN
            INSERT (type_name) VALUES (src.type_name);

        -- 2. Directors
        MERGE INTO directors tgt
        USING (
            SELECT DISTINCT TRIM(REGEXP_SUBSTR(director, '[^,]+', 1, LEVEL)) AS dir_name
            FROM (SELECT director FROM netflix_staging WHERE director IS NOT NULL)
            CONNECT BY PRIOR director = director
                   AND PRIOR SYS_GUID() IS NOT NULL
                   AND LEVEL <= REGEXP_COUNT(director, '[^,]+')
        ) src
        ON (tgt.director_name = src.dir_name)
        WHEN NOT MATCHED THEN
            INSERT (director_name) VALUES (src.dir_name);

        -- 3. Actors
        MERGE INTO actors tgt
        USING (
            SELECT DISTINCT TRIM(REGEXP_SUBSTR(cast, '[^,]+', 1, LEVEL)) AS act_name
            FROM (SELECT cast FROM netflix_staging WHERE cast IS NOT NULL)
            CONNECT BY PRIOR cast = cast
                   AND PRIOR SYS_GUID() IS NOT NULL
                   AND LEVEL <= REGEXP_COUNT(cast, '[^,]+')
        ) src
        ON (tgt.actor_name = src.act_name)
        WHEN NOT MATCHED THEN
            INSERT (actor_name) VALUES (src.act_name);

        -- 4. Genres
        MERGE INTO genres tgt
        USING (
            SELECT DISTINCT TRIM(REGEXP_SUBSTR(listed_in, '[^,]+', 1, LEVEL)) AS g_name
            FROM (SELECT listed_in FROM netflix_staging WHERE listed_in IS NOT NULL)
            CONNECT BY PRIOR listed_in = listed_in
                   AND PRIOR SYS_GUID() IS NOT NULL
                   AND LEVEL <= REGEXP_COUNT(listed_in, '[^,]+')
        ) src
        ON (tgt.genre_name = src.g_name)
        WHEN NOT MATCHED THEN
            INSERT (genre_name) VALUES (src.g_name);

        -- 5. Countries
        MERGE INTO countries tgt
        USING (
            SELECT DISTINCT TRIM(REGEXP_SUBSTR(country, '[^,]+', 1, LEVEL)) AS c_name
            FROM (SELECT country FROM netflix_staging WHERE country IS NOT NULL)
            CONNECT BY PRIOR country = country
                   AND PRIOR SYS_GUID() IS NOT NULL
                   AND LEVEL <= REGEXP_COUNT(country, '[^,]+')
        ) src
        ON (tgt.country_name = src.c_name)
        WHEN NOT MATCHED THEN
            INSERT (country_name) VALUES (src.c_name);

        -- 6. Titles
        FOR r IN (
            SELECT s.show_id,
                   t.type_id,
                   TRIM(s.title) AS title,
                   s.date_added,
                   TO_NUMBER(REGEXP_SUBSTR(s.release_year, '^\d{4}$')) AS release_year,
                   TRIM(s.rating) AS rating,
                   TO_NUMBER(REGEXP_SUBSTR(s.duration, '^\d+')) AS duration_val,
                   REGEXP_SUBSTR(s.duration, '[a-zA-Z]+$') AS duration_u,
                   s.description
            FROM netflix_staging s
            JOIN types t ON t.type_name = TRIM(s.type)
            WHERE s.show_id IS NOT NULL AND s.title IS NOT NULL
        ) LOOP
            BEGIN
                -- Resolve date in PL/SQL variable prior to SQL invocation
                v_parsed_date := parse_date_added(r.date_added);

                MERGE INTO titles tgt
                USING (SELECT r.show_id AS show_id FROM dual) src
                ON (tgt.show_id = src.show_id)
                WHEN MATCHED THEN
                    UPDATE SET
                        tgt.type_id        = r.type_id,
                        tgt.title          = r.title,
                        tgt.date_added     = v_parsed_date,
                        tgt.release_year   = NVL(r.release_year, 1900),
                        tgt.rating         = r.rating,
                        tgt.duration_value = r.duration_val,
                        tgt.duration_unit  = r.duration_u,
                        tgt.description    = r.description,
                        tgt.updated_at     = SYSTIMESTAMP
                WHEN NOT MATCHED THEN
                    INSERT (
                        show_id, type_id, title, date_added, release_year,
                        rating, duration_value, duration_unit, description
                    ) VALUES (
                        r.show_id, r.type_id, r.title, v_parsed_date,
                        NVL(r.release_year, 1900), r.rating, r.duration_val,
                        r.duration_u, r.description
                    );
            EXCEPTION
                WHEN OTHERS THEN
                    log_error(
                        p_batch_id      => p_batch_id,
                        p_module_name   => c_module || '.TITLES_UPSERT',
                        p_source_record => 'SHOW_ID: ' || r.show_id,
                        p_error_code    => SQLCODE,
                        p_error_msg     => SQLERRM,
                        p_stack_trace   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
                    );
            END;
        END LOOP;

        -- 7. Junction Tables
        INSERT /*+ APPEND */ INTO title_directors (title_id, director_id)
        SELECT DISTINCT t.title_id, d.director_id
        FROM (
            SELECT show_id, TRIM(REGEXP_SUBSTR(director, '[^,]+', 1, LEVEL)) AS dir_name
            FROM netflix_staging
            WHERE director IS NOT NULL
            CONNECT BY PRIOR show_id = show_id
                   AND PRIOR SYS_GUID() IS NOT NULL
                   AND LEVEL <= REGEXP_COUNT(director, '[^,]+')
        ) s
        JOIN titles t ON t.show_id = s.show_id
        JOIN directors d ON d.director_name = s.dir_name
        WHERE NOT EXISTS (
            SELECT 1 FROM title_directors x 
            WHERE x.title_id = t.title_id AND x.director_id = d.director_id
        );

        INSERT /*+ APPEND */ INTO title_actors (title_id, actor_id)
        SELECT DISTINCT t.title_id, a.actor_id
        FROM (
            SELECT show_id, TRIM(REGEXP_SUBSTR(cast, '[^,]+', 1, LEVEL)) AS act_name
            FROM netflix_staging
            WHERE cast IS NOT NULL
            CONNECT BY PRIOR show_id = show_id
                   AND PRIOR SYS_GUID() IS NOT NULL
                   AND LEVEL <= REGEXP_COUNT(cast, '[^,]+')
        ) s
        JOIN titles t ON t.show_id = s.show_id
        JOIN actors a ON a.actor_name = s.act_name
        WHERE NOT EXISTS (
            SELECT 1 FROM title_actors x 
            WHERE x.title_id = t.title_id AND x.actor_id = a.actor_id
        );

        INSERT /*+ APPEND */ INTO title_genres (title_id, genre_id)
        SELECT DISTINCT t.title_id, g.genre_id
        FROM (
            SELECT show_id, TRIM(REGEXP_SUBSTR(listed_in, '[^,]+', 1, LEVEL)) AS g_name
            FROM netflix_staging
            WHERE listed_in IS NOT NULL
            CONNECT BY PRIOR show_id = show_id
                   AND PRIOR SYS_GUID() IS NOT NULL
                   AND LEVEL <= REGEXP_COUNT(listed_in, '[^,]+')
        ) s
        JOIN titles t ON t.show_id = s.show_id
        JOIN genres g ON g.genre_name = s.g_name
        WHERE NOT EXISTS (
            SELECT 1 FROM title_genres x 
            WHERE x.title_id = t.title_id AND x.genre_id = g.genre_id
        );

        INSERT /*+ APPEND */ INTO title_countries (title_id, country_id)
        SELECT DISTINCT t.title_id, c.country_id
        FROM (
            SELECT show_id, TRIM(REGEXP_SUBSTR(country, '[^,]+', 1, LEVEL)) AS cntry_name
            FROM netflix_staging
            WHERE country IS NOT NULL
            CONNECT BY PRIOR show_id = show_id
                   AND PRIOR SYS_GUID() IS NOT NULL
                   AND LEVEL <= REGEXP_COUNT(country, '[^,]+')
        ) s
        JOIN titles t ON t.show_id = s.show_id
        JOIN countries c ON c.country_name = s.cntry_name
        WHERE NOT EXISTS (
            SELECT 1 FROM title_countries x 
            WHERE x.title_id = t.title_id AND x.country_id = c.country_id
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            log_error(
                p_batch_id      => p_batch_id,
                p_module_name   => c_module,
                p_source_record => 'GLOBAL_FAILURE',
                p_error_code    => SQLCODE,
                p_error_msg     => SQLERRM,
                p_stack_trace   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
            );
            RAISE;
    END process_staging_to_normalized;

END pkg_netflix_etl;
/
