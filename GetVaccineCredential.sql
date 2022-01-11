IF OBJECT_ID(N'[WAVerify].[GetVaccineCredential]',N'P') IS NOT NULL 
     DROP PROC [WAVerify].[GetVaccineCredential];
GO

CREATE PROC [WAVerify].[GetVaccineCredential]
     ( @UserID INTEGER
	 )
/*
**   WHY  GetVaccineCredential for WAVerify | Param is the UserID returned by [GetVaccineCredentialStatus]
**  WHAT  [syn_cda_vax].[dbo].[GetVaccineCredential]
** WHERE  $/DOH-EPI-CODERS/CEDAR-DevOps/Extracts/WAIIS/IIS/SQL/VaccineVerification/GetVaccineCredential.sql
**  WHEN  20210929 - Created | 20211108 - Instrumentation for logging
**   WHO  
*/
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY
	
		DECLARE @msg VARCHAR(256);
		DECLARE @sql NVARCHAR(MAX);
		DECLARE @ord INTEGER = 0;
		DECLARE @json NVARCHAR(MAX);
		DECLARE @crlf CHAR(2) = CHAR(13)+CHAR(10);
		DECLARE @debug INT = 1;
		DECLARE @LastName NVARCHAR(160);
		DECLARE @FirstName NVARCHAR(160);
		DECLARE @MiddleName NVARCHAR(160);
		DECLARE @BirthDate NVARCHAR(20); -- (yyyy-mm-dd) from DATETIME2
		DECLARE	@VaxCount INTEGER; -- WHILE loop limit
		DECLARE @VaxCode NVARCHAR(20); -- from INTEGER
		DECLARE @VaxDate NVARCHAR(20); -- (yyyy-mm-dd) from DATETIME2

		DECLARE @logStart DATETIME = ((GETDATE() AT TIME ZONE N'UTC') AT TIME ZONE 'Pacific Standard Time');
		DECLARE @logEnd DATETIME;
		DECLARE @logRslt INTEGER = -1;
		DECLARE @procName SYSNAME = N'GetVaccineCredential';
                DECLARE @paramString NVARCHAR(255) = CAST(@UserID AS VARCHAR(10));
		
		--   --   --   --   --   --   --
		SET @msg = N'Validate Parameters'; RAISERROR(@msg,10,1) WITH NOWAIT;
		--   --   --   --   --   --   --

		IF OBJECT_ID(N'tempdb..#tmp',N'U') IS NOT NULL DROP TABLE #tmp;

		--   --   --   --   --   --   --
		SET @msg = N'Get values for return elements'; RAISERROR(@msg,10,1) WITH NOWAIT;
		--   --   --   --   --   --   --

		; WITH vt
		  AS ( SELECT [ASIIS_VACC_CODE] = 2080, [CDC_VACC_CODE] = 207, [VACCINE_NAME] = N'Moderna'
		 UNION SELECT [ASIIS_VACC_CODE] = 2089, [CDC_VACC_CODE] = 208, [VACCINE_NAME] = N'Pfizer'
		 UNION SELECT [ASIIS_VACC_CODE] = 2090, [CDC_VACC_CODE] = 213, [VACCINE_NAME] = N'UNKNOWN'
		 UNION SELECT [ASIIS_VACC_CODE] = 2091, [CDC_VACC_CODE] = 210, [VACCINE_NAME] = N'AstraZeneca'
		 UNION SELECT [ASIIS_VACC_CODE] = 2092, [CDC_VACC_CODE] = 212, [VACCINE_NAME] = N'Janssen'
		 UNION SELECT [ASIIS_VACC_CODE] = 3002, [CDC_VACC_CODE] = 211, [VACCINE_NAME] = N'Novavax'
		 UNION SELECT [ASIIS_VACC_CODE] = 3015, [CDC_VACC_CODE] = 217, [VACCINE_NAME] = N'Pfizer'
		 UNION SELECT [ASIIS_VACC_CODE] = 3016, [CDC_VACC_CODE] = 218, [VACCINE_NAME] = N'Pfizer'
		 UNION SELECT [ASIIS_VACC_CODE] = 3017, [CDC_VACC_CODE] = 219, [VACCINE_NAME] = N'Pfizer'
			 )

		--   --   --   --   --   --   --

		, vm  -- Vaccination Master (specific to UserID for COVID)
		  AS ( 
                SELECT vm.[ASIIS_PAT_ID_PTR]
			 , vm.[VACC_DATE]
			 , vm.[ASIIS_FAC_ID]
			 , [VaxCode] = vt.[CDC_VACC_CODE]
			 , [ord] = ROW_NUMBER() OVER (ORDER BY vm.[VACC_DATE])
          FROM [dbo].[VACCINATION_MASTER] vm
		  JOIN vt
		    ON vm.[ASIIS_VACC_CODE] = vt.[ASIIS_VACC_CODE]
		   AND vm.[ASIIS_PAT_ID_PTR] = @UserID
		   AND vm.[DELETION_DATE] IS NULL
		     )

		--   --   --   --   --   --   --

		SELECT [UserID] = pm.[ASIIS_PAT_ID]
		     , [LastName] = pm.[PAT_LAST_NAME]
			 , [FirstName] = pm.[PAT_FIRST_NAME]
			 , [MiddleName] = pm.[PAT_MIDDLE_NAME]
			 , [BirthDate] = ISNULL(CONVERT(NVARCHAR(20),pm.[PAT_BIRTH_DATE] ,23),N'')
			 , vm.[VaxCode]
			 , [VaxDate] = CONVERT(NVARCHAR(20),vm.[VACC_DATE] ,23)
			 , vm.[ord]
		  INTO #tmp
		  FROM [dbo].[PATIENT_MASTER] pm
		  JOIN vm
		    ON pm.[ASIIS_PAT_ID] = vm.[ASIIS_PAT_ID_PTR]

		--   --   --   --   --   --   --

		; WITH hdr
		  AS (
		SELECT [VaxCount] = MAX([ord])
             , [LastName]
             , [FirstName]
             , [MiddleName]
			 , [BirthDate]
		  FROM #tmp
		 GROUP BY [LastName]
             , [FirstName]
             , [MiddleName]
			 , [BirthDate]
		     )
		SELECT @VaxCount = [VaxCount]
		     , @LastName = [LastName]
		     , @FirstName = [FirstName]
		     , @MiddleName = [MiddleName]
			 , @BirthDate = [BirthDate]
		  FROM hdr;

		--   --   --   --   --   --   --
		SET @msg = N'Return the json expression of the result set'; RAISERROR(@msg,10,1) WITH NOWAIT;
		--   --   --   --   --   --   --

		SET @json = N'
{
  "vc": {
    "type": [
      "https://smarthealth.cards#health-card",
      "https://smarthealth.cards#immunization",
      "https://smarthealth.cards#covid19"
    ],
    "credentialSubject": {
      "fhirVersion": "4.0.1",
      "fhirBundle": {
        "resourceType": "Bundle",
        "type": "collection",
        "entry": [
          {
            "fullUrl": "resource:0",
            "resource": {
              "resourceType": "Patient",
              "name": [
                {
                  "family": "' + @LastName + N'",
                  "given": [
                    "' + @FirstName + ISNULL(N'","' + @MiddleName + N'"',N'"') + N'
                  ]
                }
              ],
              "birthDate": "' + @BirthDate + N'"
            }
          }'

		WHILE @ord < @VaxCount
		BEGIN
			SET @ord = @ord + 1;

			SELECT @VaxCode = [VaxCode]
			     , @VaxDate = [VaxDate]
			  FROM #tmp
			 WHERE [ord] = @ord;

			SET @json = @json + N',
          {
            "fullUrl": "resource:' + CAST(@ord AS NVARCHAR(10)) + N'",
            "resource": {
              "resourceType": "Immunization",
              "status": "completed",
              "vaccineCode": {
                "coding": [
                  {
                    "system":"http://hl7.org/fhir/sid/cvx",
                    "code": "' + @VaxCode + N'"
                  }
                ]
              },
              "patient": {
                "reference": "resource:0"
              },
              "occurrenceDateTime": "' + @VaxDate + N'"
            }
          }'
        END

        SET @json = @json + N'
        ]
      }
    }
  }
}' ;
		IF @debug = 1 RAISERROR(@json,10,1) WITH NOWAIT;
		SET @json = REPLACE(REPLACE(@json, @crlf, ''),N'  ',N'');
		SELECT [UserVaccineCredential] = @json;

		IF @debug = 1		
		BEGIN
			SET @logRslt = 1;  -- success
			SET @logEnd = ((GETDATE() AT TIME ZONE N'UTC') AT TIME ZONE 'Pacific Standard Time');
			EXEC [WAVerify].[WriteVaxLog]
				 @procName
			   , @logStart 
			   , @logEnd
			   , @logRslt
			   , @paramString
			   , @json
         END

	END TRY

	BEGIN CATCH
        SET @logEnd = ((GETDATE() AT TIME ZONE N'UTC') AT TIME ZONE 'Pacific Standard Time');
		SET @msg = N'ERROR [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '] : ' + error_message();

		IF @debug = 1		
		BEGIN
			EXEC [WAVerify].[WriteVaxLog]
				 @procName
			   , @logStart 
			   , @logEnd
			   , @logRslt
			   , @paramString
			   , @msg
        END

		RAISERROR(@msg,16,1);
	END CATCH
END
