/*
**   WHY  Create the table and update proc for WAVerify debug logging
**  WHAT  [syn_cda_vax].[WAVerify].[WriteVaxLog]
** WHERE  $/DOH-EPI-CODERS/CEDAR-DevOps/Extracts/WAIIS/IIS/SQL/Vax_Event/cr8VaxLog.sql
**  WHEN  20211028
**   WHO  
*/
SET NOCOUNT ON;
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY

		DECLARE @msg VARCHAR(256);
		DECLARE @crlf CHAR(2) = CHAR(13)+CHAR(10)
		SET @msg = N'Create Table'; RAISERROR(@msg,10,1) WITH NOWAIT;
/*
		IF OBJECT_ID(N'[WAVerify].[VaxLog]',N'U') IS NOT NULL DROP TABLE [WAVerify].[VaxLog];

		CREATE TABLE [WAVerify].[VaxLog]
		     ( LogKey INTEGER NOT NULL IDENTITY(1,1)
			 , DateKey INTEGER NOT NULL
			 , StoredProcName SYSNAME NOT NULL
			 , dtStart DATETIME NOT NULL
			 , dtEnd DATETIME NOT NULL
			 , ParamString NVARCHAR(256) NOT NULL
			 , RsltKey INT NULL
			 , MsgString NVARCHAR(MAX) NULL
			 )
        WITH ( CLUSTERED INDEX ([LogKey]), DISTRIBUTION = HASH([DateKey]) )

*/
       SET @msg = N'Create Procedure'; RAISERROR(@msg,10,1) WITH NOWAIT;

       DECLARE @sql NVARCHAR(MAX);

       IF OBJECT_ID(N'[WAVerify].[WriteVaxLog]',N'P') IS NOT NULL DROP PROC [WAVerify].[WriteVaxLog]

	   SET @sql = N'
	   CREATE PROC [WAVerify].[WriteVaxLog]
	        ( @procname SYSNAME
			, @dtStart DATETIME
			, @dtEnd DATETIME
            , @rsltKey INTEGER
			, @paramString NVARCHAR(256)
            , @msgString NVARCHAR(MAX)
			) 
		AS 
		BEGIN
		    BEGIN TRAN
			INSERT [WAVerify].[VaxLog]
			     ( DateKey
				 , StoredProcName
                 , dtStart
				 , dtEnd
				 , RsltKey
                 , ParamString
                 , MsgString
				 )
			SELECT CAST(CONVERT(CHAR(8),@dtStart,112) AS INTEGER)
				 , @procname
                 , @dtStart
				 , @dtEnd -- [dbo].[fnGetElapsedTime](@dtStart,@dtEnd)
				 , @rsltKey
                 , @paramString
                 , @msgString;
			COMMIT TRAN
			WHILE @@TRANCOUNT > 0 ROLLBACK TRAN;
		END'

		RAISERROR(@sql,10,1) WITH NOWAIT;
		EXEC sp_executesql @sql;

	END TRY

	BEGIN CATCH
		SET @msg = N'Error in ' + ERROR_PROCEDURE() + N': [' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + N']' + @crlf + ERROR_MESSAGE();
		RAISERROR(@msg,16,1);
	END CATCH
END
