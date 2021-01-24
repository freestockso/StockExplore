IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.CalcKLineWeek') AND type in (N'P', N'PC'))
DROP PROCEDURE dbo.CalcKLineWeek
GO

-- *************** ��������: ������ K �� ***************
CREATE PROCEDURE dbo.CalcKLineWeek(@ReCalcAll INT = 0)
AS
SET NOCOUNT ON

DECLARE @startDay DATETIME
DECLARE @endDay   DATETIME

-- ���һ�������ܵ����һ��
SET @endDay   = (SELECT TOP 1 TradeDay FROM KLineDayZS WHERE StkCode = '999999' AND (DATEPART(weekday, TradeDay) = 6 OR DATEDIFF(week, TradeDay, GETDATE()) > 0) ORDER BY TradeDay DESC)

IF @ReCalcAll = 1
    BEGIN
        TRUNCATE TABLE KLineWeek
        SET @startDay = (SELECT TOP 1 TradeDay FROM KLineDayZS WHERE StkCode = '999999' ORDER BY TradeDay)
    END
ELSE
    BEGIN
        SET @startDay = (SELECT TOP 1 TradeDay
                         FROM   KLineDayZS
                         WHERE  StkCode = '999999'
                         AND    TradeDay > ISNULL((SELECT TOP 1 TradeDay FROM KLineWeek WHERE StkCode = '999999' ORDER BY TradeDay DESC), 0)
                         ORDER BY TradeDay)
    END

IF @startDay IS NULL OR @endDay IS NULL OR @startDay > @endDay
    RETURN



DECLARE @weekDiff INT
DECLARE @minWeekDiff INT = DATEDIFF(week, 0, @startDay)
DECLARE @maxWeekDiff INT = DATEDIFF(week, 0, @endDay)
DECLARE @weekStartDay DATETIME, @weekEndDay DATETIME  

SET @weekDiff = @minWeekDiff    
WHILE @weekDiff <= @maxWeekDiff
    BEGIN
        -- ȡ��ÿһ����һ������
        SET @weekStartDay = DATEADD(week, @weekDiff, 0)
        SET @weekEndDay   = DATEADD(week, @weekDiff, 4)
        
        -- �����������й�Ʊһ�ܵ� K ������
        --PRINT CONVERT(CHAR(10), @weekStartDay, 111) + ' - ' + CONVERT(CHAR(10), @weekEndDay, 111)
        INSERT INTO KLineWeek(MarkType,StkCode,TradeDay,[Open],[High],[Low],[Close],Volume,Amount)
        SELECT b.MarkType, b.StkCode, c.TradeDay, b.[Open], a.[High], a.[Low], c.[Close], a.Volume, a.Amount
          FROM
        (
            SELECT [High] = MAX([High]), [Low] = MIN([Low]), Volume = SUM(Volume), Amount = SUM(Amount), OpenDayId = MIN(RecId), CloseDayId = MAX(RecId)
              FROM KLineDay WHERE TradeDay BETWEEN @weekStartDay AND @weekEndDay GROUP BY StkCode
        ) a
        JOIN (SELECT MarkType, StkCode, [Open], RecId FROM KLineDay) b
        ON a.OpenDayId = b.RecId
        JOIN (SELECT TradeDay, [Close], RecId FROM KLineDay) c
        ON a.CloseDayId = c.RecId
        UNION ALL
        SELECT b.MarkType, b.StkCode, c.TradeDay, b.[Open], a.[High], a.[Low], c.[Close], a.Volume, a.Amount
          FROM
        (
            SELECT [High] = MAX([High]), [Low] = MIN([Low]), Volume = SUM(Volume), Amount = SUM(Amount), OpenDayId = MIN(RecId), CloseDayId = MAX(RecId)
              FROM KLineDayZS WHERE TradeDay BETWEEN @weekStartDay AND @weekEndDay GROUP BY StkCode
        ) a
        JOIN (SELECT MarkType, StkCode, [Open], RecId FROM KLineDayZS) b
        ON a.OpenDayId = b.RecId
        JOIN (SELECT TradeDay, [Close], RecId FROM KLineDayZS) c
        ON a.CloseDayId = c.RecId
        
        SET @weekDiff = @weekDiff + 1
    END

SET NOCOUNT OFF
GO
--EXEC [CalcKLineWeek] 1







IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.StatisticDayIncreaseBlock') AND type in (N'P', N'PC'))
DROP PROCEDURE dbo.StatisticDayIncreaseBlock
GO

-- *************** ��������: ͳ��ĳ���Ƿ���ǰ�İ������ ***************
CREATE PROCEDURE dbo.StatisticDayIncreaseBlock(@TradeDay SMALLDATETIME = '1900/01/01')
AS
SET NOCOUNT ON

    -- ȥ��ʱ��
    IF DATEPART(hour, @TradeDay) + DATEPART(minute, @TradeDay) > 0
        SET @TradeDay = CAST(@TradeDay AS DATE)
    
    -- û��������Ĭ�������һ��������
    IF (@TradeDay = '1900/01/01')
        SET @TradeDay = (SELECT MAX(TradeDay) FROM KLineDayZS WHERE MarkType = 'sh' AND StkCode = '999999' OR StkCode = '000001')
    
    -- ���� A�� �б�
    DECLARE @AllAList AS [CodeParmTable]
    INSERT INTO @AllAList SELECT * FROM cv_AStockCodeExcST
    
    -- �Ƿ����� 3% ���б�
    DECLARE @BigIncreaseList AS [CodeParmTable]
    INSERT INTO @BigIncreaseList
    SELECT curP.MarkType, curP.StkCode
    FROM KLineDay curP
    JOIN
    (
        SELECT a.StkCode, a.[Close] FROM KLineDay a
        JOIN (SELECT RecId = MAX(b0.RecId) FROM KLineDay b0
              WHERE b0.TradeDay < @TradeDay
                AND EXISTS (SELECT 1 FROM @AllAList WHERE MarkType = b0.MarkType AND StkCode = b0.StkCode) -- �����������б��ٶ�
              GROUP BY b0.MarkType, b0.StkCode
        ) b
        ON a.RecId = b.RecId
    ) prepP
    ON curP.StkCode = prepP.StkCode
    JOIN @AllAList rangLst
    ON   rangLst.MarkType = curP.MarkType AND rangLst.StkCode = curP.StkCode
    WHERE   curP.TradeDay = @TradeDay
        AND prepP.[Close] > 0
        AND ((curP.[Close] - prepP.[Close]) / prepP.[Close] * 100) >= 3 -- �Ƿ����� 3%

    -- ��ͣ���б�
    DECLARE @ZTList AS [CodeParmTable]
    INSERT INTO @ZTList SELECT * FROM dbo.GetZTCodeList(@TradeDay, @BigIncreaseList)
    
    -- �¹ɣ�δ���� �б�
    DECLARE @NewNotBrokenCodeList AS [CodeParmTable]
    INSERT INTO @NewNotBrokenCodeList SELECT * FROM dbo.GetNewNotBrokenCodeList(@TradeDay, @ZTList)

    -- ��ͣ���б�ȥ���¹�δ���壩
    DECLARE @ZTListExcNew AS [CodeParmTable]
    INSERT INTO @ZTListExcNew
    SELECT * FROM @ZTList a 
    WHERE NOT EXISTS (SELECT 1 FROM @NewNotBrokenCodeList b WHERE a.MarkType = b.MarkType AND a.StkCode = b.StkCode)

    -- �Ƿ����� 3% ���б�ȥ���¹�δ���壩
    DECLARE @BigIncreaseListExcNew AS [CodeParmTable]
    INSERT INTO @BigIncreaseListExcNew
    SELECT * FROM @BigIncreaseList a 
    WHERE NOT EXISTS (SELECT 1 FROM @NewNotBrokenCodeList b WHERE a.MarkType = b.MarkType AND a.StkCode = b.StkCode)


    -- ��ʾ��ͣ���б�ȥ���¹�δ���壩
    SELECT  a.MarkType, a.StkCode, b.StkName,
            ContinueCount = dbo.GetRatioContinueCount(a.StkCode, 9.9, 1, @TradeDay, '1'),
            StkBlock = dbo.GetStockBlockFormat(a.StkCode)
    FROM @ZTListExcNew a JOIN StockHead b ON a.MarkType = b.MarkType AND a.StkCode = b.StkCode AND b.StkType = '1' 
    ORDER BY dbo.GetRatioContinueCount(a.StkCode, 9.9, 1, @TradeDay, '1') DESC

    -- ��ʾ�Ƿ����� 3% ���б�ȥ���¹�δ���壩
    SELECT  a.MarkType, a.StkCode, b.StkName,
            ContinueCount = dbo.GetRatioContinueCount(a.StkCode, 3, 1, @TradeDay, '1'),
            StkBlock = dbo.GetStockBlockFormat(a.StkCode)
    FROM @BigIncreaseList a JOIN StockHead b ON a.MarkType = b.MarkType AND a.StkCode = b.StkCode AND b.StkType = '1'
    ORDER BY dbo.GetRatioContinueCount(a.StkCode, 3, 1, @TradeDay, '1') DESC

    -- ��ʾ��ͣ�壨ȥ���¹�δ���壩���ڰ��ͳ��
    SELECT Stk.BKType, Stk.BKName, Stk.StkCount, BK.BKCount, 
           Prec = CAST( ROUND(CAST(Stk.StkCount AS FLOAT) / BK.BKCount * 100, 1) AS VARCHAR(10)) + '%',
           GroupOrder = ROW_NUMBER() OVER ( PARTITION BY Stk.BKType 
                                            ORDER BY CAST(CASE Stk.StkCount WHEN 1 THEN 0 ELSE Stk.StkCount END AS FLOAT) / BK.BKCount DESC, 
                                                Stk.StkCount DESC, BK.BKCount ASC),
           StockList = dbo.GetBKStockCodeInRange(Stk.BKType, Stk.BKName, @ZTListExcNew)
    FROM 
    (
        SELECT b.BKType, b.BKName, StkCount = COUNT(1)
        FROM @ZTListExcNew a JOIN StockBlock b ON a.StkCode = b.StkCode
        GROUP BY b.BKType, b.BKName
    ) Stk
    JOIN
    (
        SELECT BKType, BKName, BKCount = COUNT(1) FROM StockBlock
        GROUP BY BKType, BKName
    ) BK ON Stk.BKType = BK.BKType AND Stk.BKName = BK.BKName
    ORDER BY --Stk.BKType, 
            CASE Stk.BKType
                WHEN N'����'     THEN '0'
                WHEN N'��ҵ'     THEN '1'
                WHEN N'��ҵϸ��' THEN '2'
                WHEN N'����'     THEN '3'
                WHEN N'���'     THEN '4'
                WHEN N'ָ��'     THEN '5'
                ELSE Stk.BKType
            END,
            CAST(CASE Stk.StkCount WHEN 1 THEN 0 ELSE Stk.StkCount END AS FLOAT) / BK.BKCount DESC, -- ��ֻ��һ�����ŵ�����ȥ
            Stk.StkCount DESC, 
            BK.BKCount ASC



    -- ��ʾ�Ƿ����� 3% �ģ�ȥ���¹�δ���壩���ڰ��ͳ��
    SELECT Stk.BKType, Stk.BKName, Stk.StkCount, BK.BKCount, 
           Prec = CAST( ROUND(CAST(Stk.StkCount AS FLOAT) / BK.BKCount * 100, 1) AS VARCHAR(10)) + '%',
           GroupOrder = ROW_NUMBER() OVER ( PARTITION BY Stk.BKType 
                                            ORDER BY CAST(CASE Stk.StkCount WHEN 1 THEN 0 ELSE Stk.StkCount END AS FLOAT) / BK.BKCount DESC, 
                                                Stk.StkCount DESC, BK.BKCount ASC),
           StockList = dbo.GetBKStockCodeInRange(Stk.BKType, Stk.BKName, @BigIncreaseList)
    FROM
    (
        SELECT b.BKType, b.BKName, StkCount = COUNT(1)
        FROM @BigIncreaseList a JOIN StockBlock b ON a.StkCode = b.StkCode
        GROUP BY b.BKType, b.BKName
    ) Stk
    JOIN
    (
        SELECT BKType, BKName, BKCount = COUNT(1) FROM StockBlock
        GROUP BY BKType, BKName
    ) BK ON Stk.BKType = BK.BKType AND Stk.BKName = BK.BKName
    ORDER BY --Stk.BKType, 
            CASE Stk.BKType
                WHEN N'����'     THEN '0'
                WHEN N'��ҵ'     THEN '1'
                WHEN N'��ҵϸ��' THEN '2'
                WHEN N'����'     THEN '3'
                WHEN N'���'     THEN '4'
                WHEN N'ָ��'     THEN '5'
                ELSE Stk.BKType
            END,
            CAST(CASE Stk.StkCount WHEN 1 THEN 0 ELSE Stk.StkCount END AS FLOAT) / BK.BKCount DESC, -- ��ֻ��һ�����ŵ�����ȥ
            Stk.StkCount DESC, 
            BK.BKCount ASC


SET NOCOUNT OFF
GO
--EXEC dbo.StatisticDayIncreaseBlock '2017/10/09'








IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.StatisticDayDecreaseBlock') AND type in (N'P', N'PC'))
DROP PROCEDURE dbo.StatisticDayDecreaseBlock
GO

-- *************** ��������: ͳ��ĳ�յ�����ǰ�İ������ ***************
CREATE PROCEDURE dbo.StatisticDayDecreaseBlock(@TradeDay SMALLDATETIME = '1900/01/01')
AS
SET NOCOUNT ON

    -- ȥ��ʱ��
    IF DATEPART(hour, @TradeDay) + DATEPART(minute, @TradeDay) > 0
        SET @TradeDay = CAST(@TradeDay AS DATE)
    
    -- û��������Ĭ�������һ��������
    IF (@TradeDay = '1900/01/01')
        SET @TradeDay = (SELECT MAX(TradeDay) FROM KLineDayZS WHERE MarkType = 'sh' AND StkCode = '999999' OR StkCode = '000001')
    
    -- ���� A�� �б�
    DECLARE @AllAList AS [CodeParmTable]
    INSERT INTO @AllAList SELECT * FROM cv_AStockCodeExcST
    
    -- �������� 3% ���б�
    DECLARE @BigDecreaseList AS [CodeParmTable]
    INSERT INTO @BigDecreaseList
    SELECT curP.MarkType, curP.StkCode
    FROM KLineDay curP
    JOIN
    (
        SELECT a.StkCode, a.[Close] FROM KLineDay a
        JOIN (SELECT RecId = MAX(b0.RecId) FROM KLineDay b0
              WHERE b0.TradeDay < @TradeDay
                AND EXISTS (SELECT 1 FROM @AllAList WHERE MarkType = b0.MarkType AND StkCode = b0.StkCode) -- �����������б��ٶ�
              GROUP BY b0.MarkType, b0.StkCode
        ) b
        ON a.RecId = b.RecId
    ) prepP
    ON curP.StkCode = prepP.StkCode
    JOIN @AllAList rangLst
    ON   rangLst.MarkType = curP.MarkType AND rangLst.StkCode = curP.StkCode
    WHERE   curP.TradeDay = @TradeDay
        AND prepP.[Close] > 0
        AND ((curP.[Close] - prepP.[Close]) / prepP.[Close] * 100) <= -3 -- �������� 3%

    -- ��ͣ���б�
    DECLARE @DTList AS [CodeParmTable]
    INSERT INTO @DTList SELECT * FROM dbo.GetDTCodeList(@TradeDay, @BigDecreaseList)


    -- ��ʾ��ͣ���б�
    SELECT  a.MarkType, a.StkCode, b.StkName,
            ContinueCount = dbo.GetRatioContinueCount(a.StkCode, -9.9, 0, @TradeDay, '1'),
            StkBlock = dbo.GetStockBlockFormat(a.StkCode)
    FROM @DTList a JOIN StockHead b ON a.MarkType = b.MarkType AND a.StkCode = b.StkCode AND b.StkType = '1' 
    ORDER BY dbo.GetRatioContinueCount(a.StkCode, -9.9, 0, @TradeDay, '1') DESC

    -- ��ʾ�������� 3% ���б�
    SELECT  a.MarkType, a.StkCode, b.StkName,
            ContinueCount = dbo.GetRatioContinueCount(a.StkCode, -3, 0, @TradeDay, '1'),
            StkBlock = dbo.GetStockBlockFormat(a.StkCode)
    FROM @BigDecreaseList a JOIN StockHead b ON a.MarkType = b.MarkType AND a.StkCode = b.StkCode AND b.StkType = '1'
    ORDER BY dbo.GetRatioContinueCount(a.StkCode, -3, 0, @TradeDay, '1') DESC

    -- ��ʾ��ͣ�����ڰ��ͳ��
    SELECT Stk.BKType, Stk.BKName, Stk.StkCount, BK.BKCount, 
           Prec = CAST( ROUND(CAST(Stk.StkCount AS FLOAT) / BK.BKCount * 100, 1) AS VARCHAR(10)) + '%',
           GroupOrder = ROW_NUMBER() OVER ( PARTITION BY Stk.BKType 
                                            ORDER BY CAST(CASE Stk.StkCount WHEN 1 THEN 0 ELSE Stk.StkCount END AS FLOAT) / BK.BKCount DESC, 
                                                Stk.StkCount DESC, BK.BKCount ASC),
           StockList = dbo.GetBKStockCodeInRange(Stk.BKType, Stk.BKName, @DTList)
    FROM 
    (
        SELECT b.BKType, b.BKName, StkCount = COUNT(1)
        FROM @DTList a JOIN StockBlock b ON a.StkCode = b.StkCode
        GROUP BY b.BKType, b.BKName
    ) Stk
    JOIN
    (
        SELECT BKType, BKName, BKCount = COUNT(1) FROM StockBlock
        GROUP BY BKType, BKName
    ) BK ON Stk.BKType = BK.BKType AND Stk.BKName = BK.BKName
    ORDER BY --Stk.BKType, 
            CASE Stk.BKType
                WHEN N'����'     THEN '0'
                WHEN N'��ҵ'     THEN '1'
                WHEN N'��ҵϸ��' THEN '2'
                WHEN N'����'     THEN '3'
                WHEN N'���'     THEN '4'
                WHEN N'ָ��'     THEN '5'
                ELSE Stk.BKType
            END,
            CAST(CASE Stk.StkCount WHEN 1 THEN 0 ELSE Stk.StkCount END AS FLOAT) / BK.BKCount DESC, -- ��ֻ��һ�����ŵ�����ȥ
            Stk.StkCount DESC, 
            BK.BKCount ASC



    -- ��ʾ�������� 3% �����ڰ��ͳ��
    SELECT Stk.BKType, Stk.BKName, Stk.StkCount, BK.BKCount, 
           Prec = CAST( ROUND(CAST(Stk.StkCount AS FLOAT) / BK.BKCount * 100, 1) AS VARCHAR(10)) + '%',
           GroupOrder = ROW_NUMBER() OVER ( PARTITION BY Stk.BKType 
                                            ORDER BY CAST(CASE Stk.StkCount WHEN 1 THEN 0 ELSE Stk.StkCount END AS FLOAT) / BK.BKCount DESC, 
                                                Stk.StkCount DESC, BK.BKCount ASC),
           StockList = dbo.GetBKStockCodeInRange(Stk.BKType, Stk.BKName, @BigDecreaseList)
    FROM
    (
        SELECT b.BKType, b.BKName, StkCount = COUNT(1)
        FROM @BigDecreaseList a JOIN StockBlock b ON a.StkCode = b.StkCode
        GROUP BY b.BKType, b.BKName
    ) Stk
    JOIN
    (
        SELECT BKType, BKName, BKCount = COUNT(1) FROM StockBlock
        GROUP BY BKType, BKName
    ) BK ON Stk.BKType = BK.BKType AND Stk.BKName = BK.BKName
    ORDER BY --Stk.BKType, 
            CASE Stk.BKType
                WHEN N'����'     THEN '0'
                WHEN N'��ҵ'     THEN '1'
                WHEN N'��ҵϸ��' THEN '2'
                WHEN N'����'     THEN '3'
                WHEN N'���'     THEN '4'
                WHEN N'ָ��'     THEN '5'
                ELSE Stk.BKType
            END,
            CAST(CASE Stk.StkCount WHEN 1 THEN 0 ELSE Stk.StkCount END AS FLOAT) / BK.BKCount DESC, -- ��ֻ��һ�����ŵ�����ȥ
            Stk.StkCount DESC, 
            BK.BKCount ASC


SET NOCOUNT OFF
GO
--EXEC dbo.StatisticDayDecreaseBlock '2017/10/09'
