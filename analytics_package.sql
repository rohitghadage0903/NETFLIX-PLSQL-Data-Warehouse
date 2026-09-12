

CREATE OR REPLACE PACKAGE pkg_netflix_analytics AS
    e_title_not_found     EXCEPTION;
    e_invalid_page_param  EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_title_not_found, -20001);
    PRAGMA EXCEPTION_INIT(e_invalid_page_param, -20002);

    TYPE t_cursor IS REF CURSOR;

    FUNCTION get_content_count_by_country(p_country_name IN VARCHAR2) RETURN NUMBER;
    
    FUNCTION get_top_contributors(
        p_role_type IN VARCHAR2 DEFAULT 'ACTOR', 
        p_limit     IN NUMBER DEFAULT 5
    ) RETURN t_cursor;

    FUNCTION get_yearly_genre_distribution(p_release_year IN NUMBER) RETURN t_cursor;

    PROCEDURE get_catalog_paginated(
        p_genre_name   IN VARCHAR2 DEFAULT NULL,
        p_type_name    IN VARCHAR2 DEFAULT NULL,
        p_release_year IN NUMBER   DEFAULT NULL,
        p_page_num     IN NUMBER   DEFAULT 1,
        p_page_size    IN NUMBER   DEFAULT 10,
        o_total_rows   OUT NUMBER,
        o_results      OUT t_cursor
    );
END pkg_netflix_analytics;
/

CREATE OR REPLACE PACKAGE BODY pkg_netflix_analytics AS

    FUNCTION get_content_count_by_country(p_country_name IN VARCHAR2) RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(DISTINCT tc.title_id)
        INTO v_count
        FROM countries c
        JOIN title_countries tc ON c.country_id = tc.country_id
        WHERE UPPER(c.country_name) = UPPER(TRIM(p_country_name));

        RETURN v_count;
    END get_content_count_by_country;

    FUNCTION get_top_contributors(
        p_role_type IN VARCHAR2 DEFAULT 'ACTOR',
        p_limit     IN NUMBER DEFAULT 5
    ) RETURN t_cursor IS
        v_cur t_cursor;
    BEGIN
        IF UPPER(p_role_type) = 'ACTOR' THEN
            OPEN v_cur FOR
                SELECT a.actor_name AS name, COUNT(ta.title_id) AS total_titles
                FROM actors a
                JOIN title_actors ta ON a.actor_id = ta.actor_id
                GROUP BY a.actor_id, a.actor_name
                ORDER BY total_titles DESC, a.actor_name ASC
                FETCH FIRST p_limit ROWS ONLY;
        ELSIF UPPER(p_role_type) = 'DIRECTOR' THEN
            OPEN v_cur FOR
                SELECT d.director_name AS name, COUNT(td.title_id) AS total_titles
                FROM directors d
                JOIN title_directors td ON d.director_id = td.director_id
                GROUP BY d.director_id, d.director_name
                ORDER BY total_titles DESC, d.director_name ASC
                FETCH FIRST p_limit ROWS ONLY;
        ELSE
            RAISE_APPLICATION_ERROR(-20003, 'Invalid role type. Use ACTOR or DIRECTOR.');
        END IF;

        RETURN v_cur;
    END get_top_contributors;

    FUNCTION get_yearly_genre_distribution(p_release_year IN NUMBER) RETURN t_cursor IS
        v_cur t_cursor;
    BEGIN
        OPEN v_cur FOR
            SELECT g.genre_name, COUNT(tg.title_id) AS title_count
            FROM genres g
            JOIN title_genres tg ON g.genre_id = tg.genre_id
            JOIN titles t ON tg.title_id = t.title_id
            WHERE t.release_year = p_release_year
            GROUP BY g.genre_id, g.genre_name
            ORDER BY title_count DESC;

        RETURN v_cur;
    END get_yearly_genre_distribution;

    PROCEDURE get_catalog_paginated(
        p_genre_name   IN VARCHAR2 DEFAULT NULL,
        p_type_name    IN VARCHAR2 DEFAULT NULL,
        p_release_year IN NUMBER   DEFAULT NULL,
        p_page_num     IN NUMBER   DEFAULT 1,
        p_page_size    IN NUMBER   DEFAULT 10,
        o_total_rows   OUT NUMBER,
        o_results      OUT t_cursor
    ) IS
        v_offset NUMBER;
    BEGIN
        IF p_page_num < 1 OR p_page_size < 1 THEN
            RAISE_APPLICATION_ERROR(-20002, 'Page number and page size must be positive integers.');
        END IF;

        v_offset := (p_page_num - 1) * p_page_size;

        SELECT COUNT(DISTINCT t.title_id)
        INTO o_total_rows
        FROM titles t
        JOIN types tp ON t.type_id = tp.type_id
        LEFT JOIN title_genres tg ON t.title_id = tg.title_id
        LEFT JOIN genres g ON tg.genre_id = g.genre_id
        WHERE (p_genre_name IS NULL OR UPPER(g.genre_name) = UPPER(TRIM(p_genre_name)))
          AND (p_type_name IS NULL OR UPPER(tp.type_name) = UPPER(TRIM(p_type_name)))
          AND (p_release_year IS NULL OR t.release_year = p_release_year);

        OPEN o_results FOR
            SELECT t.show_id,
                   t.title,
                   tp.type_name,
                   t.release_year,
                   t.rating,
                   t.duration_value || ' ' || t.duration_unit AS runtime
            FROM titles t
            JOIN types tp ON t.type_id = tp.type_id
            WHERE t.title_id IN (
                SELECT DISTINCT t_sub.title_id
                FROM titles t_sub
                JOIN types tp_sub ON t_sub.type_id = tp_sub.type_id
                LEFT JOIN title_genres tg_sub ON t_sub.title_id = tg_sub.title_id
                LEFT JOIN genres g_sub ON tg_sub.genre_id = g_sub.genre_id
                WHERE (p_genre_name IS NULL OR UPPER(g_sub.genre_name) = UPPER(TRIM(p_genre_name)))
                  AND (p_type_name IS NULL OR UPPER(tp_sub.type_name) = UPPER(TRIM(p_type_name)))
                  AND (p_release_year IS NULL OR t_sub.release_year = p_release_year)
            )
            ORDER BY t.release_year DESC, t.title ASC
            OFFSET v_offset ROWS FETCH NEXT p_page_size ROWS ONLY;

    END get_catalog_paginated;

END pkg_netflix_analytics;
/
