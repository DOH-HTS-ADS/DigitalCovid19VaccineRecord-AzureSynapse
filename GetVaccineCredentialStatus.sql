IF OBJECT_ID(N'[WAVerify].[GetVaccineCredentialStatus]',N'P') IS NOT NULL 
     DROP PROC [WAVerify].[GetVaccineCredentialStatus];
GO

CREATE PROC [WAVerify].[GetVaccineCredentialStatus]
     ( @FirstName NVARCHAR(160)
	 , @LastName NVARCHAR(160)
	 , @DateOfBirth NVARCHAR(50)
	 , @PhoneNumber NVARCHAR(50)
	 , @EmailAddress NVARCHAR(255)
	 )
/*
**   WHY  GetVaccineCredentialStatus for WAVerify
**  WHAT  [syn-cda-test.sql.azuresynapse.net].[syn_cda_vax].[dbo].[GetVaccineCredentialStatus]
** WHERE  $/DOH-EPI-CODERS/CEDAR-DevOps/Extracts/WAIIS/IIS/SQL/VaccineVerification/GetVaccineCredentialStatus.sql
**  WHEN  20210929 - created | 20211108 - intrumentation for logging
**   WHO  Jim.Atwater@doh.wa.gov | jamesatwater@hotmail.com
*/
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY
	
		DECLARE @msg VARCHAR(256) = N'Failed on case -1';
		DECLARE @sql NVARCHAR(MAX);
		DECLARE @crlf CHAR(2) = CHAR(13)+CHAR(10);
		DECLARE @comma CHAR(1) = CHAR(44)
		DECLARE @debug INT = 1
		DECLARE @logStart DATETIME = ((GETDATE() AT TIME ZONE N'UTC') AT TIME ZONE 'Pacific Standard Time');
		DECLARE @logEnd DATETIME;
		DECLARE @logMatchKey INTEGER = -1;
        DECLARE @paramString NVARCHAR(255)
		DECLARE @procName SYSNAME = N'GetVaccineCredentialStatus'
		DECLARE @UserID INTEGER = Null;
		
		SET @PhoneNumber = REPLACE(@PhoneNumber,N'-',N'');
        SET @paramString = '"' + ISNULL(@FirstName,'') + '"|"'+ ISNULL(@LastName,'') + '"|"'+ ISNULL(@DateOfBirth,'') + '"|"' + ISNULL(@PhoneNumber,'') + '"|"'+ ISNULL(@EmailAddress,'') + '"'

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
		  JOIN vt
		    ON vm.[ASIIS_VACC_CODE] = vt.[ASIIS_VACC_CODE]  -- columnstore  | partition by vax code
		   AND vm.[DELETION_DATE] IS NULL
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

        , rslt
          AS (
        SELECT pm.[ASIIS_PAT_ID]
          FROM [dbo].[PATIENT_MASTER] pm
		  JOIN vm
		    ON pm.[ASIIS_PAT_ID] = vm.[ASIIS_PAT_ID_PTR]
		  LEFT JOIN prList 
		    ON prList.[ASIIS_PAT_ID_PTR] = pm.[ASIIS_PAT_ID]
		 WHERE @FirstName = pm.[PAT_FIRST_NAME]
		   AND @LastName = pm.[PAT_LAST_NAME]
		   AND 0 = DATEDIFF(DAY,@DateOfBirth,pm.[PAT_BIRTH_DATE])
		   AND ( CHARINDEX(@PhoneNumber,prList.[PHONE_LIST]) > 0
		      OR @EmailAddress = pm.[ADDRESS_EMAIL]
			   ) 
             )

		SELECT @UserID = [ASIIS_PAT_ID]
			 , @msg = N'Matched - strict'
		  FROM rslt;

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
        SET @logEnd = ((GETDATE() AT TIME ZONE N'UTC') AT TIME ZONE 'Pacific Standard Time');
		SET @msg = N'ERROR [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '] : ' + error_message();
        IF @debug = 1
            EXEC [WAVerify].[WriteVaxLog]
				 @procName
			   , @logStart 
			   , @logEnd
			   , @UserID
			   , @paramString
			   , @msg
			   ;

		RAISERROR(@msg,16,1);
	END CATCH
END
