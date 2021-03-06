EXEC [dbo].[DropProcedureIfExists] 'Integration', 'GetEmployeePhotoUpdates'

PRINT 'Creating procedure [Integration].[GetEmployeePhotoUpdates]'
GO

CREATE PROCEDURE [Integration].[GetEmployeePhotoUpdates]
@LastCutoff datetime2(7),
@NewCutoff datetime2(7)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EndOfTime datetime2(7) = '99991231 23:59:59.9999999';

    CREATE TABLE #EmployeePhotoChanges
    (
        [WWI Employee ID] int,
		[Block ID] int,
        [Photo] varbinary NULL,
        [Valid From] datetime2(7),
        [Valid To] datetime2(7)
    );

    DECLARE @PersonID int;
    DECLARE @ValidFrom datetime2(7);
	DECLARE @Photo varbinary(max)

    -- need to find any employee changes that have occurred, including during the initial load

    DECLARE EmployeePhotoChangeList CURSOR FAST_FORWARD READ_ONLY
    FOR
    SELECT p.PersonID,
           p.ValidFrom,
		   CAST(p.Photo as varbinary(max))
    FROM [Application].People_Archive AS p
    WHERE p.ValidFrom > @LastCutoff
    AND p.ValidFrom <= @NewCutoff
    AND p.IsEmployee <> 0
	AND p.Photo IS NOT NULL
    UNION ALL
    SELECT p.PersonID,
           p.ValidFrom,
		   CAST(p.Photo as varbinary(max))
    FROM [Application].People AS p
    WHERE p.ValidFrom > @LastCutoff
    AND p.ValidFrom <= @NewCutoff
    AND p.IsEmployee <> 0
	AND p.Photo IS NOT NULL
    ORDER BY ValidFrom;

    OPEN EmployeePhotoChangeList;
    FETCH NEXT FROM EmployeePhotoChangeList INTO @PersonID, @ValidFrom,@Photo;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT #EmployeePhotoChanges
            ([WWI Employee ID],
			[Block ID],
			Photo,
            [Valid From],
			[Valid To])
        SELECT
		@PersonID,
		block_id,
		CONVERT(varbinary(8000),SUBSTRING(@Photo,start_index,byte_count)),
		@ValidFrom,
		NULL
		FROM Integration.Split_VarbinaryFunc(@Photo)

        FETCH NEXT FROM EmployeePhotoChangeList INTO @PersonID, @ValidFrom,@Photo;
    END;

    CLOSE EmployeePhotoChangeList;
    DEALLOCATE EmployeePhotoChangeList;

    -- add an index to make lookups faster

    CREATE INDEX IX_EmployeeChanges ON #EmployeePhotoChanges ([WWI Employee ID], [Valid From]);

    -- work out the [Valid To] value by taking the [Valid From] of any row that's for the same entry but later
    -- otherwise take the end of time

    UPDATE cc
    SET [Valid To] = COALESCE((SELECT MIN([Valid From]) FROM #EmployeePhotoChanges AS cc2
                                                        WHERE cc2.[WWI Employee ID] = cc.[WWI Employee ID]
                                                        AND cc2.[Valid From] > cc.[Valid From]), @EndOfTime)
    FROM #EmployeePhotoChanges AS cc;

    SELECT [WWI Employee ID],
			[Block ID],
			Photo,
            [Valid From],
			[Valid To]
    FROM #EmployeePhotoChanges
    ORDER BY [Valid From];

    DROP TABLE #EmployeePhotoChanges;

    RETURN 0;
END;
