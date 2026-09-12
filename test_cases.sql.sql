-- ============================================================================
-- 05_TEST_CASES.SQL: Sample Mock Load, Pipeline Run & Verification Blocks
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- 1. Ingest Synthetic Mock Records into Staging
BEGIN
    DELETE FROM netflix_staging;

    INSERT INTO netflix_staging (show_id, type, title, director, cast, country, date_added, release_year, rating, duration, listed_in, description)
    VALUES ('s1', 'Movie', 'Dick Johnson Is Dead', 'Kirsten Johnson', 'Michael Hilow, Andrea', 'United States', 'September 25, 2021', '2020', 'PG-13', '90 min', 'Documentaries', 'A father nearing the end of his life.');

    INSERT INTO netflix_staging (show_id, type, title, director, cast, country, date_added, release_year, rating, duration, listed_in, description)
    VALUES ('s2', 'TV Show', 'Blood & Water', 'Ama Qamata', 'Ama Qamata, Khosi Ngema, Gail Mabalane', 'South Africa', 'September 24, 2021', '2021', 'TV-MA', '2 Seasons', 'International TV Shows, TV Dramas, TV Mysteries', 'After crossing paths at a party, a teen sets out to find her sister.');

    INSERT INTO netflix_staging (show_id, type, title, director, cast, country, date_added, release_year, rating, duration, listed_in, description)
    VALUES ('s3', 'TV Show', 'Ganglands', 'Julien Leclercq', 'Sami Bouajila, Tracy Gotoas, Samuel Jouy', 'France', 'September 24, 2021', '2021', 'TV-MA', '1 Season', 'Crime TV Shows, International TV Shows, TV Action & Adventure', 'A skilled thief and his apprentice get caught in a turf war.');

    INSERT INTO netflix_staging (show_id, type, title, director, cast, country, date_added, release_year, rating, duration, listed_in, description)
    VALUES ('s4', 'Movie', 'Midnight Mass', 'Mike Flanagan', 'Kate Siegel, Zach Gilford, Hamish Linklater', 'United States', 'September 24, 2021', '2021', 'TV-MA', '1 Season', 'TV Dramas, TV Horror, TV Mysteries', 'An isolated island community experiences miraculous events.');

    -- Deliberate bad record to test duration/year parsing & error isolation
    INSERT INTO netflix_staging (show_id, type, title, director, cast, country, date_added, release_year, rating, duration, listed_in, description)
    VALUES ('s_err', 'Movie', 'Malformed Year Title', 'Unknown Director', 'Actor A', 'India', 'Invalid Date', 'Year99', 'PG', '120 min', 'Comedies', 'Faulty release year record.');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('>> Staging loaded successfully.');
END;
/

-- 2. Execute ETL Pipeline
DECLARE
    v_batch_id VARCHAR2(64) := 'BATCH-' || TO_CHAR(SYSDATE, 'YYYYMMDD-HH24MISS');
BEGIN
    DBMS_OUTPUT.PUT_LINE('>> Starting ETL execution for Batch: ' || v_batch_id);
    pkg_netflix_etl.process_staging_to_normalized(p_batch_id => v_batch_id);
    DBMS_OUTPUT.PUT_LINE('>> ETL execution finished.');
END;
/

-- 3. Run Analytics & Assert Schema Outputs
DECLARE
    v_cur       pkg_netflix_analytics.t_cursor;
    v_name      VARCHAR2(150);
    v_count     NUMBER;
    v_genre     VARCHAR2(100);
    v_total     NUMBER;
    
    -- Record holders for paginated catalog
    v_show_id   VARCHAR2(20);
    v_title     VARCHAR2(500);
    v_type      VARCHAR2(30);
    v_year      NUMBER;
    v_rating    VARCHAR2(20);
    v_runtime   VARCHAR2(30);
BEGIN
    DBMS_OUTPUT.PUT_LINE('---------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('TEST 1: Metric - US Titles Count');
    DBMS_OUTPUT.PUT_LINE('US Total: ' || pkg_netflix_analytics.get_content_count_by_country('United States'));

    DBMS_OUTPUT.PUT_LINE('---------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('TEST 2: Metric - Top 3 Actors');
    v_cur := pkg_netflix_analytics.get_top_contributors('ACTOR', 3);
    LOOP
        FETCH v_cur INTO v_name, v_count;
        EXIT WHEN v_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('Actor: ' || RPAD(v_name, 25) || ' | Appearances: ' || v_count);
    END LOOP;
    CLOSE v_cur;

    DBMS_OUTPUT.PUT_LINE('---------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('TEST 3: Metric - 2021 Genre Distribution');
    v_cur := pkg_netflix_analytics.get_yearly_genre_distribution(2021);
    LOOP
        FETCH v_cur INTO v_genre, v_count;
        EXIT WHEN v_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('Genre: ' || RPAD(v_genre, 30) || ' | Count: ' || v_count);
    END LOOP;
    CLOSE v_cur;

    DBMS_OUTPUT.PUT_LINE('---------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('TEST 4: Paginated Query (TV Shows, Page 1, Size 2)');
    pkg_netflix_analytics.get_catalog_paginated(
        p_genre_name   => NULL,
        p_type_name    => 'TV Show',
        p_release_year => NULL,
        p_page_num     => 1,
        p_page_size    => 2,
        o_total_rows   => v_total,
        o_results      => v_cur
    );
    DBMS_OUTPUT.PUT_LINE('Total Matched Records: ' || v_total);
    LOOP
        FETCH v_cur INTO v_show_id, v_title, v_type, v_year, v_rating, v_runtime;
        EXIT WHEN v_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('[' || v_show_id || '] ' || RPAD(v_title, 20) || ' (' || v_year || ') - ' || v_runtime);
    END LOOP;
    CLOSE v_cur;
END;
/

-- 4. Verify Triggers and Auditing Functionality
DECLARE
    v_audit_count NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('---------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('TEST 5: Testing Audit Trigger on UPDATE');

    UPDATE titles
    SET rating = 'R', duration_value = 95
    WHERE show_id = 's1';
    COMMIT;

    SELECT COUNT(*) INTO v_audit_count
    FROM titles_audit_log
    WHERE show_id = 's1' AND action_type = 'UPDATE';

    DBMS_OUTPUT.PUT_LINE('Audit entries found for update: ' || v_audit_count);
END;
/

-- 5. Inspect Verification Counts
SELECT 'types' AS table_name, COUNT(*) AS cnt FROM types
UNION ALL
SELECT 'directors', COUNT(*) FROM directors
UNION ALL
SELECT 'actors', COUNT(*) FROM actors
UNION ALL
SELECT 'genres', COUNT(*) FROM genres
UNION ALL
SELECT 'countries', COUNT(*) FROM countries
UNION ALL
SELECT 'titles', COUNT(*) FROM titles
UNION ALL
SELECT 'title_actors (junction)', COUNT(*) FROM title_actors
UNION ALL
SELECT 'title_genres (junction)', COUNT(*) FROM title_genres
UNION ALL
SELECT 'titles_audit_log', COUNT(*) FROM titles_audit_log
UNION ALL
SELECT 'etl_error_log', COUNT(*) FROM etl_error_log;