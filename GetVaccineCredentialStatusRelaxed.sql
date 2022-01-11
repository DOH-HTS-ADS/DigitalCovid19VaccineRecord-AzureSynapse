IF OBJECT_ID(N'[WAVerify].[GetVaccineCredentialStatusRelaxed]',N'P') IS NOT NULL 
	 DROP PROC [WAVerify].[GetVaccineCredentialStatusRelaxed];
GO

CREATE PROC [WAVerify].[GetVaccineCredentialStatusRelaxed] 
     ( @FirstName [NVARCHAR](160)
	 , @LastName [NVARCHAR](160)
	 , @DateOfBirth [NVARCHAR](50)
	 , @PhoneNumber [NVARCHAR](50)
	 , @EmailAddress [NVARCHAR](256) 
	 )
/*
**   WHY  Implememnt Vaccine Credential Status Check with California "relaxed" matching logic
**  WHAT  GetVaccineCredentialStatusRelaxed.sql
** WHERE  $\CEDAR-DevOps\Reports\WAVerify
**  WHEN  20211010 - created | 20211021 - update per CA Matching Logic | 20211108 - intrumentation for logging  | 20211119 - Added multi-row failure message
**   WHO  
*/
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY

		DECLARE @msg NVARCHAR(MAX) = N'Failed on case -1';
		DECLARE @crlf CHAR(2) = CHAR(13)+CHAR(10);
		DECLARE @quot CHAR(1) = CHAR(34)
		DECLARE @comma CHAR(1) = CHAR(44)
		DECLARE @delim CHAR(1) = CHAR(124);
		DECLARE @bitmask INTEGER = 0;
		DECLARE @rc INTEGER = 0;
		DECLARE @UserID INTEGER = NULL;
		DECLARE @MatchCase INTEGER = -1;
		DECLARE @dtStart DATETIME = DATEADD(YEAR,-2,GETUTCDATE());
		DECLARE @dtEnd DATETIME = GETUTCDATE();

        DECLARE @DEBUG int = 1
		DECLARE @logStart DATETIME = ((GETDATE() AT TIME ZONE N'UTC') AT TIME ZONE 'Pacific Standard Time');
		DECLARE @logEnd DATETIME;
		DECLARE @logMatchKey INTEGER = -1;
		DECLARE @procName SYSNAME = N'GetVaccineCredentialStatusRelaxed';
        DECLARE @paramString NVARCHAR(255);
		SET @paramString = @quot + ISNULL(@FirstName,'') 
		     + @quot + @delim + @quot + ISNULL(@LastName,'') 
			 + @quot + @delim + @quot + ISNULL(@DateOfBirth,'') 
			 + @quot + @delim + @quot + ISNULL(@PhoneNumber,'') 
			 + @quot + @delim + @quot + ISNULL(@EmailAddress,'') 
			 + @quot;

		DECLARE @bFName TINYINT = 1;
		DECLARE @bLName TINYINT = 2;
		DECLARE @bDOB   TINYINT = 4;
		DECLARE @bPhone TINYINT = 8;
		DECLARE @bEmail TINYINT = 16;

		DECLARE @match0 TINYINT = @bPhone + @bFName + @bLName + @bDOB;
		DECLARE @match1 TINYINT = @bEmail + @bFName + @bLName + @bDOB;
		DECLARE @match2 TINYINT = @bPhone + @bFName + @bLName;
		DECLARE @match3 TINYINT = @bEmail + @bFName + @bLName;
		DECLARE @match4 TINYINT = @bPhone + @bFName + @bDOB;
		DECLARE @match5 TINYINT = @bEmail + @bFName + @bDOB;
		DECLARE @match6 TINYINT = @bPhone + @bLName + @bDOB;
		DECLARE @match7 TINYINT = @bEmail + @bLName + @bDOB;
		DECLARE @match8 TINYINT = @bPhone + @bDOB;
		DECLARE @match9 TINYINT = @bEmail + @bDOB;
		
		SET @PhoneNumber = REPLACE(@PhoneNumber,N'-',N'');
		SET @PhoneNumber = 
			CASE LEFT(@PhoneNumber,1) 
			WHEN N'1' THEN RIGHT(@PhoneNumber,LEN(@PhoneNumber)-1) 
			ELSE @PhoneNumber 
			END ;

		; WITH vt
		  AS ( SELECT [ASIIS_VACC_CODE] = 2080  --, [CDC_VACC_CODE] = 207, [VACCINE_NAME] = N'Moderna'
		 UNION SELECT [ASIIS_VACC_CODE] = 2089  --, [CDC_VACC_CODE] = 208, [VACCINE_NAME] = N'Pfizer'
		 UNION SELECT [ASIIS_VACC_CODE] = 2090  --, [CDC_VACC_CODE] = 213, [VACCINE_NAME] = N'UNKNOWN'
		 UNION SELECT [ASIIS_VACC_CODE] = 2091  --, [CDC_VACC_CODE] = 210, [VACCINE_NAME] = N'AstraZeneca'
		 UNION SELECT [ASIIS_VACC_CODE] = 2092  --, [CDC_VACC_CODE] = 212, [VACCINE_NAME] = N'Janssen'
		 UNION SELECT [ASIIS_VACC_CODE] = 3002  --, [CDC_VACC_CODE] = 211, [VACCINE_NAME] = N'Novavax'
		 UNION SELECT [ASIIS_VACC_CODE] = 3015  --, [CDC_VACC_CODE] = 217, [VACCINE_NAME] = N'Pfizer'
		 UNION SELECT [ASIIS_VACC_CODE] = 3016  --, [CDC_VACC_CODE] = 218, [VACCINE_NAME] = N'Pfizer'
		 UNION SELECT [ASIIS_VACC_CODE] = 3017  --, [CDC_VACC_CODE] = 219, [VACCINE_NAME] = N'Pfizer'
			 )

        , vm
		  AS ( 
        SELECT [ASIIS_PAT_ID_PTR]
          FROM [dbo].[VACCINATION_MASTER] vm
         WHERE EXISTS 
		     ( SELECT 1
			     FROM vt
		        WHERE vm.[ASIIS_VACC_CODE] = vt.[ASIIS_VACC_CODE]
             )
		   AND vm.[DELETION_DATE] IS NULL
		   AND vm.[VACC_DATE] BETWEEN @dtStart AND @dtEnd  -- last two years
		 GROUP BY [ASIIS_PAT_ID_PTR]
		     )

        , pr
          AS ( 
        SELECT pr.[ASIIS_PAT_ID_PTR]
		     , pr.[PHONE_NUMBER]
	      FROM [dbo].[PHONE_RESERVE] pr
		  JOIN vm
		    ON pr.[ASIIS_PAT_ID_PTR] = vm.[ASIIS_PAT_ID_PTR]
         WHERE EXISTS 
             ( SELECT 1
                 FROM vm
                WHERE pr.[ASIIS_PAT_ID_PTR] = vm.[ASIIS_PAT_ID_PTR]
             )
         GROUP BY pr.[ASIIS_PAT_ID_PTR]
		     , pr.[PHONE_NUMBER]
             )

        , prList
		  AS (
		SELECT [ASIIS_PAT_ID_PTR]
		     , [PHONE_LIST] = STRING_AGG([PHONE_NUMBER],@comma)
		  FROM pr
		 GROUP BY [ASIIS_PAT_ID_PTR]
		     )

          , bitmask
            AS (
          SELECT pm.[ASIIS_PAT_ID]
               , [MatchValue] = 
                 CASE @FirstName 
                 WHEN pm.[PAT_FIRST_NAME] 
                 THEN @bFname 
                 ELSE 0 END
               + CASE @LastName 
                 WHEN pm.[PAT_LAST_NAME] 
                 THEN @bLName 
                 ELSE 0 END
               + CASE 0 
                 WHEN DATEDIFF(DAY,@DateOfBirth,pm.[PAT_BIRTH_DATE]) 
                 THEN @bDOB 
                 ELSE 0 END
               + CASE WHEN CHARINDEX(@PhoneNumber,prList.[PHONE_LIST]) > 0
                 THEN @bPhone
                 ELSE 0 END
               + CASE @EmailAddress 
                 WHEN pm.[ADDRESS_EMAIL] 
                 THEN @bEmail 
                 ELSE 0 END
            FROM [dbo].[PATIENT_MASTER] pm
            LEFT JOIN prList
              ON pm.[ASIIS_PAT_ID] = prList.[ASIIS_PAT_ID_PTR]
           WHERE EXISTS 
               ( SELECT 1
                   FROM vm
                  WHERE pm.[ASIIS_PAT_ID] = vm.[ASIIS_PAT_ID_PTR]
               )
               )

          , scoredRslt
		    AS (
          SELECT [ASIIS_PAT_ID]
               , [MatchCase] = 
                    CASE 
                    WHEN [MatchValue] & @match0 = @match0 THEN 0
                    WHEN [MatchValue] & @match1 = @match1 THEN 1
                    WHEN [MatchValue] & @match2 = @match2 THEN 2
                    WHEN [MatchValue] & @match3 = @match3 THEN 3
                    WHEN [MatchValue] & @match4 = @match4 THEN 4
                    WHEN [MatchValue] & @match5 = @match5 THEN 5
                    WHEN [MatchValue] & @match6 = @match6 THEN 6
                    WHEN [MatchValue] & @match7 = @match7 THEN 7
                    WHEN [MatchValue] & @match8 = @match8 THEN 8
                    WHEN [MatchValue] & @match9 = @match9 THEN 9
                    ELSE NULL
                    END
            FROM bitmask
           WHERE [MatchValue] <> 0
               )

          , rankedRslt
            AS (
          SELECT [ASIIS_PAT_ID]
               , [MatchCase]
               , [rr] = DENSE_RANK() OVER (ORDER BY [MatchCase])  -- returns order of quality of match across all patients
               , [rc] = COUNT(*) OVER (PARTITION BY [MatchCase])  -- returns number of patients at each match case level
            FROM scoredRslt
           WHERE [MatchCase] IS NOT NULL
               )

          SELECT @UserID = 
					CASE -- return UserID when there is only one best match
					WHEN [rc] = 1
					THEN [ASIIS_PAT_ID] 
					ELSE NULL 
					END
			   , @msg = 
                    CASE 
                    WHEN [MatchCase] < 0 THEN N'No match'
                    WHEN [rc] > 1 THEN N'Failed with multiple matches'
                    WHEN [MatchCase] >= 0 THEN N'Matched'
                    ELSE N'Unknown match'
                    END 
				  + N' on case ' + CAST(ISNULL([MatchCase],-1) AS VARCHAR(10))
            FROM rankedRslt
           WHERE [rr] = 1  -- return the best match
			   ;

--          SELECT @UserID;
          SELECT [UserID] = @UserID
		       , [msg] = @msg;

          IF @debug = 1
		  BEGIN
			  SET @logEnd = ((GETDATE() AT TIME ZONE N'UTC') AT TIME ZONE 'Pacific Standard Time');
			  EXEC [WAVerify].[WriteVaxLog]
				   @procName
				 , @logStart 
				 , @logEnd
				 , @UserID
				 , @paramString
				 , @msg
				 ;
           END

    END TRY

	BEGIN CATCH
		SET @msg = N'ERROR [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ']: ' + error_message();
          IF @debug = 1
		  BEGIN
			  SET @logEnd = ((GETDATE() AT TIME ZONE N'UTC') AT TIME ZONE 'Pacific Standard Time');
			  EXEC [WAVerify].[WriteVaxLog]
				   @procName
				 , @logStart 
				 , @logEnd
				 , @UserID
				 , @paramString
				 , @msg
				 ;
           END
		RAISERROR(@msg,16,1);
	END CATCH
END
GO
