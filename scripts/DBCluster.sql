CREATE DATABASE rpa_jobs
COLLATE Modern_Spanish_CI_AS; 
USE rpa_jobs;
GO
/****** Object:  Table [dbo].[job_target_data]    Script Date: 22/12/2023 3:38:42 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[job_target_data](
	[job_name] [nvarchar](100) NULL,
	[rpa_row_key] [nvarchar](100) NULL,
	[rpa_host_name] [nvarchar](100) NULL,
	[rpa_status] [nvarchar](20) NULL,
	[rpa_status_change_date] [datetime] NULL,
	[rpa_status_finish_date] [datetime] NULL,
	[rpa_outcome_message] [nvarchar](200) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[job_target_data_master]    Script Date: 22/12/2023 3:38:42 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[job_target_data_master](
	[job_name] [nvarchar](100) NULL,
	[total_rows] [int] NULL,
 CONSTRAINT [uk_job_name] UNIQUE NONCLUSTERED 
(
	[job_name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  StoredProcedure [dbo].[createDataMaster]    Script Date: 22/12/2023 3:38:42 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[createDataMaster]
    @job_name NVARCHAR(100)
AS
BEGIN
    INSERT INTO job_target_data_master (job_name, total_rows)
    VALUES (@job_name, 0); -- Se inicia con total_rows en 0
END;
GO
/****** Object:  StoredProcedure [dbo].[getAvailableDataRowForJob]    Script Date: 22/12/2023 3:38:42 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[getAvailableDataRowForJob]
   @job_name NVARCHAR(100),
   @available_record NVARCHAR(100) OUTPUT
AS
BEGIN
   DECLARE @appLckRet INT = 0;
   DECLARE @availDataMaster INT = 0;
   DECLARE @resName NVARCHAR(110);
   SET @resName = CONCAT(N'RowMutex', @job_name)

   BEGIN TRANSACTION criticalZone
   
   -- Use TRY-CATCH to handle errors gracefully
   BEGIN TRY
       EXEC @appLckRet = sys.sp_getapplock
            @Resource = @resName 
           ,@LockMode = 'Exclusive'
           ,@LockOwner = 'Transaction'
           ,@LockTimeout = 1500 --ms
       ;

       -- Exclusive access granted
       IF (@appLckRet >= 0)
       BEGIN

	      -- Check for the existance of datamaster
		  SELECT TOP 1 @availDataMaster = total_rows
		  FROM [dbo].[job_target_data_master]
		  WHERE  job_name = @job_name
		  ;
          
		  -- If no available row found, rollback and raise an error
          IF (@@ROWCOUNT = 0)
          BEGIN
             ROLLBACK;
             THROW 59999, '__NO_DATA_MASTER__', 1;
          END;

          -- Query the available row
          SELECT TOP 1 @available_record = rpa_row_key
          FROM   [dbo].[job_target_data]
          WHERE  job_name = @job_name
          AND    rpa_status = 'FREE'
          ;
          
		  -- If no available row found, rollback and raise an error
          IF (@@ROWCOUNT = 0)
          BEGIN
             ROLLBACK;
             THROW 60000, 'THERE ARE NO ROWS AVAILABLE FOR PROCESSING', 1;
          END;
          
          -- Reserve the record for processing
          UPDATE [dbo].[job_target_data]
             SET rpa_status = 'PROC',
			     rpa_host_name = HOST_NAME(),
                 rpa_status_change_date = GETDATE(),
                 rpa_status_finish_date = NULL,
                 rpa_outcome_message = NULL
           WHERE rpa_row_key = @available_record;

          -- Release the criticalZone
          COMMIT;
      END
   END TRY
   BEGIN CATCH
       -- If an error occurs, rollback and throw the error
       IF @@TRANCOUNT > 0
           ROLLBACK;
       THROW;
   END CATCH
END;
GO
/****** Object:  StoredProcedure [dbo].[insJobTargetData]    Script Date: 22/12/2023 3:38:42 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[insJobTargetData]
    @job_name NVARCHAR(100),
    @rpa_row_key NVARCHAR(100)
AS
BEGIN
    INSERT INTO job_target_data (job_name, rpa_row_key, rpa_host_name, rpa_status, rpa_outcome_message, rpa_status_change_date, rpa_status_finish_date)
    VALUES (@job_name, @rpa_row_key, HOST_NAME(), 'FREE', NULL, GETDATE(), NULL);
END;
GO
/****** Object:  StoredProcedure [dbo].[removeDataMaster]    Script Date: 22/12/2023 3:38:42 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[removeDataMaster]
    @job_name NVARCHAR(100)
AS
BEGIN
    DELETE FROM job_target_data_master
    WHERE job_name = @job_name;
END;
GO
/****** Object:  StoredProcedure [dbo].[updateDataMaster]    Script Date: 22/12/2023 3:38:42 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Procedimiento almacenado para actualizar el total_rows en job_target_data_master
CREATE PROCEDURE [dbo].[updateDataMaster]
    @job_name NVARCHAR(100),
    @total_rows INT
AS
BEGIN
    UPDATE job_target_data_master
    SET total_rows = @total_rows
    WHERE job_name = @job_name;
END;
GO
/****** Object:  StoredProcedure [dbo].[updateTargetData]    Script Date: 22/12/2023 3:38:42 p. m. ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[updateTargetData]
    @job_name NVARCHAR(100),
    @rpa_row_key NVARCHAR(100),
    @rpa_status NVARCHAR(20),
    @rpa_outcome_message NVARCHAR(200)
AS
BEGIN
    UPDATE job_target_data
       SET rpa_status = @rpa_status,
           rpa_outcome_message = @rpa_outcome_message,
           rpa_status_finish_date = GETDATE()
     WHERE job_name = @job_name 
	   AND rpa_row_key = @rpa_row_key;
END;
GO
