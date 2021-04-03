CREATE OR REPLACE PROCEDURE `dw.sp_post_master`(slice_start DATE, slice_end DATE) 
BEGIN
    BEGIN
        CREATE OR REPLACE TEMPORARY TABLE `stg_records` AS
        SELECT
            -- reddit records
            redd.post_id
            , redd.sub AS subreddit
            , redd.title
            , CAST(redd.score AS INT64) AS score
            , redd.upvote_ratio
            -- reddit calculated fields
            , redd.track AS parsed_track
            , redd.artist AS parsed_artist
            , CASE WHEN COALESCE(redd.track, redd.artist) IS NOT NULL THEN TRUE ELSE FALSE END AS is_parsed
            , CASE WHEN NULLIF(spot.track_id, 'None') IS NOT NULL THEN TRUE ELSE FALSE END AS is_found
            -- spotify records
            , NULLIF(spot.track_id, 'None') AS track_id
            , spot.track_name
            , CAST(spot.track_popularity AS INT64) AS track_popularity
            , spot.album_id
            , spot.album_name
            , spot.artist_id
            , spot.artist_name
            , CASE WHEN spot.supporting_artists IS NOT NULL 
                THEN SPLIT(spot.supporting_artists, ', ') ELSE NULL 
            END AS supporting_artists 
            -- spotify track features
            , spot.danceability
            , spot.energy
            , spot.valence
            , spot.tempo
            , spot.loudness
            , spot.speechiness
            , spot.instrumentalness
            , spot.acousticness
            , spot.liveness
            , INTEGER(ROUND(spot.duration_ms / 1000)) AS track_duration_seconds
            -- meta date related
            , redd.dt AS _meta_dt
            , FALSE AS _meta_is_current
            , FALSE AS _meta_is_original
        FROM `extract.reddit` AS redd
        LEFT JOIN `extract.spotify` AS spot
            ON redd.dt=spot.dt
            AND redd.sub=spot.sub
            AND redd.post_id=spot.post_id
        WHERE redd.dt BETWEEN slice_start AND slice_end;
    END;
    
    -- replace and insert records
    -- update meta fields for any posts that made it in staging
    BEGIN
        DELETE `dw.post_master` AS bs
        WHERE EXISTS (
            SELECT 1 FROM `stg_records` AS stg 
            WHERE bs._meta_dt=stg._meta_dt
            AND bs.post_id=stg.post_id
        );
    
        INSERT `dw.post_master` 
            (post_id, subreddit, title, score, upvote_ratio, parsed_track, parsed_artist, is_parsed, is_found, track_id, track_name, track_popularity, album_id, album_name, artist_id, artist_name, supporting_artists, danceability, energy, valence, tempo, loudness, speechiness, instrumentalness, acousticness, _meta_dt, _meta_is_current, _meta_is_original)
        SELECT 
            post_id, subreddit, title, score, upvote_ratio, parsed_track, parsed_artist, is_parsed, is_found, track_id, track_name, track_popularity, album_id, album_name, artist_id, artist_name, supporting_artists, danceability, energy, valence, tempo, loudness, speechiness, instrumentalness, acousticness, _meta_dt, _meta_is_current, _meta_is_original
        FROM `stg_records`;
    
        UPDATE `dw.post_master` AS bs 
        SET 
            bs._meta_is_current = meta_vals._meta_is_current 
            , bs._meta_is_original = meta_vals._meta_is_original
        FROM (
            SELECT
                post_id
                , _meta_dt
                , CASE WHEN ROW_NUMBER() OVER(PARTITION BY post_id ORDER BY _meta_dt DESC) = 1 THEN TRUE ELSE FALSE END AS _meta_is_current 
                , CASE WHEN ROW_NUMBER() OVER(PARTITION BY post_id ORDER BY _meta_dt ASC) = 1 THEN TRUE ELSE FALSE END AS _meta_is_original 
            FROM `dw.post_master` 
            WHERE post_id IN (SELECT DISTINCT post_id FROM `stg_records`)
        ) AS meta_vals
        WHERE bs._meta_dt=meta_vals._meta_dt
        AND bs.post_id=meta_vals.post_id;
    END;
END;
