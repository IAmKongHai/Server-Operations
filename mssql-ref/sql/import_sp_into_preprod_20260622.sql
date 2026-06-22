-- ============================================================
-- 目的: 把完整库 medicalassistance 有、但 _preprod 缺的存储过程补进 _preprod
-- 来源: medicalassistance_20260620_sql.sql (完整库结构)
-- 数量: 146 个, 全部为 type=P 存储过程 (其中 80 个带 v2~v7 版本号后缀)
--
-- 【执行顺序】必须先补表/列, 再补 SP:
--   第 1 步: import_into_preprod_20260622.sql   (建 11 表 + 补 40 列)
--   第 2 步: 本脚本                              (补 146 SP)
--   原因: 多个 SP 引用第 1 步新建的表(如 tblbatchloamappingdetails /
--         tbldoctorewtjournal)和新补的列, 顺序反了会因缺对象而行为异常。
--
-- 【已核验】
--   - 146 个 SP 定义内均无 medicalassistance_replicated 跨库引用, 不会重新引入断链
--   - 全部通过 SET PARSEONLY 语法校验
--   - 这些 SP 在 preprod 当前不存在, 直接 CREATE 不会冲突
--
-- 【执行前必做】备份 preprod (改库守则)
-- ============================================================
USE [medicalassistance_preprod];
GO

-- ---- sp_deleteinvalidclaims ----
CREATE PROCEDURE [dbo].[sp_deleteinvalidclaims]
	-- Add the parameters for the stored procedure here
	
	@membercode		Int,
	@providercode	Int,	
	@encodedby		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lmembercode		Int				= @membercode,
			@lprovidercode		Int				= @providercode,		
			@lencodedby			Int				= @encodedby

    ---- Create Temporary Table -----

	IF (SELECT name FROM tempdb.sys.tables WHERE name LIKE '%#temp_invalidclaims%')  IS NOT NULL 
	BEGIN 
		DROP TABLE #temp_invalidclaims
	END

	CREATE TABLE #temp_invalidclaims
	(
		claimcode Int
	)

	INSERT INTO #temp_invalidclaims(claimcode)
	SELECT claimcode
	FROM tblclaims WITH(NOLOCK) 
	WHERE caseno = '' AND CAST(dateencoded as DATE) = CAST(GETDATE() AS DATE) 
	AND encodedby = @lencodedby AND providercode = @lprovidercode AND membercode = @membercode

	IF ((SELECT count(claimcode) FROM #temp_invalidclaims) > 0)
	BEGIN
		DELETE FROM tblclaimprogress WHERE claimcode IN (SELECT claimcode FROM #temp_invalidclaims WITH(NOLOCK))
		DELETE FROM tblclaimdeductions WHERE claimcode IN (SELECT claimcode FROM #temp_invalidclaims WITH(NOLOCK))
		DELETE FROM tblclaimdetails WHERE claimcode IN (SELECT claimcode FROM #temp_invalidclaims WITH(NOLOCK))
		DELETE FROM tblclaimdiagnosis WHERE claimcode IN (SELECT claimcode FROM #temp_invalidclaims WITH(NOLOCK))
		DELETE FROM tblclaims WHERE claimcode IN (SELECT claimcode FROM #temp_invalidclaims WITH(NOLOCK))
	END

	DROP TABLE #temp_invalidclaims

END
GO

-- ---- sp_getaccountbenefitplandetailsv2 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getaccountbenefitplandetailsv2] --13977
	-- Add the parameters for the stored procedure here
	
	@plancode	Int

AS
BEGIN
	-- SET NOCOUNT WITH(NOLOCK) WHERE added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lplancode	Int	 = @plancode

	SELECT a.plancode, a.compcode, a.contractcode, a.amdtcode, 
	a.pecwaived, a.reimbursementrate, a.programtype, a.selectiontype,  a.sumassured, a.privilegecare,
	sobplancode = LTRIM(RTRIM(a.sobplancode)),
	approved = CASE WHEN a.approvedby <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
	benefitplancode = LTRIM(RTRIM(a.classcode)) +'-'+ ISNULL(LTRIM(RTRIM(a.sobplancode)), '') + Iif(a.amdtcode <> 0, '-AMDT', ''),
	planname = LTRIM(RTRIM(a.planname)),
	membertype = LTRIM(RTRIM(a.membertype)),
	membertypemajor = LTRIM(RTRIM(a.membertypemajor)),
	membertypespillover = LTRIM(RTRIM(a.membertypespillover)), 
	customplancode = LTRIM(RTRIM(a.customplancode)),
	philhealth = ISNULL(a.philhealth, 0),
	philhealthname = CASE WHEN a.philhealth = 0 THEN 'OP Not Required' 
						  WHEN a.philhealth = 1 THEN 'Independent' 
						  WHEN a.philhealth = 2 THEN 'On Top of PH' 
						  WHEN a.philhealth = 3 THEN 'Inclusive' 
						  WHEN a.philhealth = 4 THEN 'Independent (But Required)'
						  ELSE '' END,
	a.limitamount,
	a.limitamountmajor,
	a.limitamountac,
	a.limitamountspillover,
	a.excessguarantee,
	plantype = IIF(a.plantype <> 0, a.plantype, a.limitsetup),
	a.benefittype, a.displaysalesportal, a.hibamount, a.archive,
	a.classification, classificationname = CASE WHEN a.classification = 0 THEN 'BOTH PRINCIPAL AND DEPENDENT'
												WHEN a.classification = 1 THEN 'PRINCIPAL ONLY'
												WHEN a.classification = 2 THEN 'DEPENDENT ONLY'
												ELSE '' END,
	claimservices = LTRIM(RTRIM(a.claimservices)), a.provideraccess,
	provideraccessname = CASE WHEN a.provideraccess = 0 THEN 'BOTH HOSPITAL & CLINIC' 
							  WHEN a.provideraccess = 1 THEN 'HOSPITAL ONLY'
							  WHEN a.provideraccess = 2 THEN 'CLINIC ONLY'
							  ELSE '' END,
	a.remarks, a.interperiodprin, a.interperioddep, 
	a.coinsurance, a.preparedby, a.prepareddate, a.actuaryby, a.actuarydate, a.approvedby, 
	a.approveddate, a.deductible, a.claimserviceitems,  
	a.coinsurancemajor, a.coinsurancespillover, a.deductiblemajor, a.deductiblespillover, a.interperiodddprin, a.coininnerlimit, 
	a.interperioddddep, 
	a.applicablegender, applicablegendername = CASE WHEN a.applicablegender = 1 THEN 'FEMALE ONLY'
													WHEN a.applicablegender = 2 THEN 'MALE ONLY'
													WHEN a.applicablegender = 3 THEN 'BOTH MALE AND FEMALE'
													ELSE '' END,
	a.usemajormed, a.sharedlimit, a.adminfee, a.brokerfee, a.coinsurancere, a.coinsurancemajorre, 
	a.coinsurancespilloverre, a.coinsurancelimit, a.computeinner, a.effectivity, a.expiry,
	contractyearfrom = ISNULL(c.contractyearfrom, 0.00),
	a.deductiblere, a.deductiblemajorre, a.deductiblespilloverre,  a.limitamountmajorac, a.callless, a.prorated, a.clbufferlimit, 
	preparedbyname = ISNULL(LTRIM(RTRIM(d.username)), ''), 
	actuarybyname = ISNULL(LTRIM(RTRIM(e.username)), ''), 
	approvedbyname = ISNULL(LTRIM(RTRIM(f.username)), ''), 
	a.classcode,
	classname = ISNULL(LTRIM(RTRIM(g.classname)), ''), 
	plandesc = LTRIM(RTRIM(a.plandesc)),
	ISNULL(k.description, '') AS programtypename,
	renewalsobplancode = ISNULL(LTRIM(RTRIM(l.sobplancode)), ''), 
	renewalplanname= ISNULL(LTRIM(RTRIM(l.planname)), ''), 
	a.limitsetup,
	limitcode = ISNULL(LTRIM(RTRIM(h.recordcode)), ''),
	sacode = ISNULL(i.sacode, 0),
	roomcategcode = ISNULL(LTRIM(RTRIM(j.benefitcode)), ''), 
	roomcategname = ISNULL(LTRIM(RTRIM(j.description)), ''), 
	roomlimitamount = ISNULL(i.limitamount, 0.00),
	roomlimitfrequency = ISNULL(i.limitfrequency, 0.00),
	roomcovered = ISNULL(LTRIM(RTRIM(i.membertype)), ''), 
	a.limitsetupothers 
	FROM tblcompanybenefitplan a WITH(NOLOCK)
	OUTER APPLY (SELECT billingschedule, expiry, contractyearfrom FROM tblcompanycontractyears c WITH(NOLOCK) WHERE a.contractcode = c.contractcode) c 
	OUTER APPLY (SELECT username FROM tblusers d WITH(NOLOCK) WHERE a.preparedby = d.userno) d
	OUTER APPLY (SELECT username FROM tblusers e WITH(NOLOCK) WHERE a.actuaryby = e.userno) e
	OUTER APPLY (SELECT username FROM tblusers f WITH(NOLOCK) WHERE a.approvedby = f.userno) f 
	OUTER APPLY (SELECT classname FROM tblcompanyclasses g WITH(NOLOCK) WHERE a.classcode = g.classcode AND a.compcode= g.compcode AND a.contractcode = g.contractcode) g
	OUTER APPLY (SELECT recordcode FROM tblgentables h WITH(NOLOCK) WHERE a.limitsetup = h.recordno AND h.tablename = 'PLAN LIMIT') h
	OUTER APPLY (SELECT sacode, roomlimit, limitamount, membertype, membertypemajor, limitfrequency FROM tblcompanybenefitlimits i WITH(NOLOCK) WHERE a.plancode = i.plancode AND i.roomlimit = 1) i
	OUTER APPLY (SELECT benefitcode, description FROM tblbenefitsa j WITH(NOLOCK) WHERE i.sacode = j.sacode) j
	OUTER APPLY (SELECT description FROM tblprovidergroups k WITH(NOLOCK) WHERE a.programtype = k.groupno) k
	OUTER APPLY (SELECT sobplancode, planname FROM tblcompanybenefitplan l WITH(NOLOCK) WHERE a.renewalplancode = l.plancode) l
	WHERE a.plancode = @lplancode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getaccountclassbillingv3 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getaccountclassbillingv3] --2808,5068, 1, 25
	-- Add the parameters for the stored procedure here
	
	@searchkey			Varchar(100),
	@compcode			Int,
	@contractcode		Int,
	@templatetype		Int,
	@productcode		Int,
	@vattype			Int,
	@billingschedule	Int,
	@effectivityfrom	Smalldatetime,
	@effectivityto		Smalldatetime,
	@expiryfrom			Smalldatetime,
	@expiryto			Smalldatetime,
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lsearchkey			Varchar(100)	= @searchkey,
			@lcompcode			Int				= @compcode,
			@lcontractcode		Int				= @contractcode,
			@ltemplatetype		Int				= @templatetype,
			@lproductcode		Int				= @productcode,
			@lvattype			Int				= @vattype,
			@lbillingschedule	Int				= @billingschedule,
			@leffectivityfrom	Smalldatetime	= @effectivityfrom,
			@leffectivityto		Smalldatetime	= @effectivityto,
			@lexpiryfrom		Smalldatetime	= @expiryfrom,
			@lexpiryto			Smalldatetime	= @expiryto,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lnodata			Int				= 0
		
	--IF (@lcompcode = 0 AND @lcontractcode = 0 AND @leffectivity = '1/1/1900' AND @lexpiry = '1/1/1900')
	--	BEGIN
	--		SET @lnodata = 1;
	--	END

	SELECT @rowcount = COUNT(1)
	FROM tblcompanyclassesbilling a WITH(NOLOCK)
	OUTER APPLY (SELECT b.username FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
	WHERE ((a.compcode = @lcompcode)
	AND ((@lcontractcode = 0 AND a.detno <> 0) OR (@lcontractcode <> 0 AND a.contractcode = @lcontractcode))
	AND ((@ltemplatetype = 0 AND a.detno <> 0) OR (@ltemplatetype <> 0 AND a.templatetype = @ltemplatetype))
	AND ((@lproductcode = 0 AND a.detno <> 0) OR (@lproductcode <> 0 AND a.productcode = @lproductcode))
	AND ((@lvattype = 0 AND a.detno <> 0) OR (@lvattype <> 0 AND a.vattype = @lvattype))
	AND ((@lbillingschedule = 0 AND a.detno <> 0) OR (@lbillingschedule <> 0 AND a.billingschedule = @lbillingschedule))
	AND ((@lsearchkey = '' AND a.detno <> 0) OR (@lsearchkey <> '' AND a.premiumclasscode LIKE '%'+@lsearchkey+'%' OR a.premiumclassname LIKE '%'+@lsearchkey+'%'))
	AND ((@leffectivityfrom = '1/1/1900' AND a.detno <> 0) OR ((@leffectivityfrom <> '1/1/1900' AND @leffectivityto <> '1/1/1900') AND (CAST(a.effectivity AS DATE) >= CAST(@leffectivityfrom AS DATE) AND CAST(a.effectivity AS DATE) <= CAST(@leffectivityto AS DATE))))
	AND ((@lexpiryfrom = '1/1/1900' AND a.detno <> 0) OR ((@lexpiryfrom <> '1/1/1900' AND @lexpiryto <> '1/1/1900') AND (CAST(a.expiry AS DATE) >= CAST(@lexpiryfrom AS DATE) AND CAST(a.expiry AS DATE) <= CAST(@lexpiryto AS DATE))))) 
	OPTION(RECOMPILE)

    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		( 	
			SELECT a.detno, a.contractcode, a.dateencoded, a.billingschedule, a.templatetype,
			billingscheduledesc = CASE a.billingschedule WHEN 1 THEN 'Monthly' WHEN 2 THEN 'Quarterly' WHEN 3 THEN 'Semi-Annual' WHEN 4 THEN 'Annual' ELSE '' END,
			a.effectivity,a.expiry, a.displaysalesportal,
			a.productcode,
			productlinecode = ISNULL(LTRIM(RTRIM(c.productlinecode)), ''),
			productline = ISNULL(LTRIM(RTRIM(c.productline)), ''),
			billclasscode = LTRIM(RTRIM(a.premiumclasscode)),
			billclassname = LTRIM(RTRIM(a.premiumclassname)), 
			billclassdesc = LTRIM(RTRIM(a.premiumclassdesc)), 
			products = (SELECT Count(premiumcode) FROM tblcompanypremiums WHERE billclassdetno = a.detno),
			benefitplan = (SELECT Count(plancode) FROM tblcompanybenefitplan WHERE classcode = a.premiumclasscode),
			encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
			a.vattype,
			vattypename = CASE  WHEN a.vattype = 1 THEN 'VATable'
								WHEN a.vattype = 2 THEN 'VAT-Exempt'
								WHEN a.vattype = 3 THEN 'Zero-Rated'
								WHEN a.vattype = 4 THEN 'Non-Vat'
								ELSE '' END,
			a.renewalclass,
			renewalclasscode = ISNULL(LTRIM(RTRIM(d.premiumclasscode)), ''),
			renewalclassname = ISNULL(LTRIM(RTRIM(d.premiumclassname)), ''),
			a.roomcategory, roomcategorycode = ISNULL(LTRIM(RTRIM(e.benefitcode)), ''),
			roomcategorydesc = ISNULL(LTRIM(RTRIM(e.description)), '')
			FROM tblcompanyclassesbilling a WITH(NOLOCK)
			OUTER APPLY (SELECT b.username FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
			OUTER APPLY (SELECT productcode, productlinecode, productline FROM tblproductlines c WITH(NOLOCK) WHERE a.productcode = c.productcode) c
			OUTER APPLY (SELECT detno, premiumclasscode, premiumclassname FROM tblcompanyclassesbilling d WITH(NOLOCK) WHERE a.renewalclass = d.detno) d
			OUTER APPLY (SELECT benefitcode, description FROM tblbenefitsa e WITH(NOLOCK) WHERE a.roomcategory = e.sacode) e
			WHERE ((a.compcode = @lcompcode)
			AND ((@lcontractcode = 0 AND a.detno <> 0) OR (@lcontractcode <> 0 AND a.contractcode = @lcontractcode))
			AND ((@ltemplatetype = 0 AND a.detno <> 0) OR (@ltemplatetype <> 0 AND a.templatetype = @ltemplatetype))
			AND ((@lproductcode = 0 AND a.detno <> 0) OR (@lproductcode <> 0 AND a.productcode = @lproductcode))
			AND ((@lvattype = 0 AND a.detno <> 0) OR (@lvattype <> 0 AND a.vattype = @lvattype))
			AND ((@lbillingschedule = 0 AND a.detno <> 0) OR (@lbillingschedule <> 0 AND a.billingschedule = @lbillingschedule))
			AND ((@lsearchkey = '' AND a.detno <> 0) OR (@lsearchkey <> '' AND a.premiumclasscode LIKE '%'+@lsearchkey+'%' OR a.premiumclassname LIKE '%'+@lsearchkey+'%'))
			AND ((@leffectivityfrom = '1/1/1900' AND a.detno <> 0) OR ((@leffectivityfrom <> '1/1/1900' AND @leffectivityto <> '1/1/1900') AND (CAST(a.effectivity AS DATE) >= CAST(@leffectivityfrom AS DATE) AND CAST(a.effectivity AS DATE) <= CAST(@leffectivityto AS DATE))))
			AND ((@lexpiryfrom = '1/1/1900' AND a.detno <> 0) OR ((@lexpiryfrom <> '1/1/1900' AND @lexpiryto <> '1/1/1900') AND (CAST(a.expiry AS DATE) >= CAST(@lexpiryfrom AS DATE) AND CAST(a.expiry AS DATE) <= CAST(@lexpiryto AS DATE)))))
		) result
		ORDER BY billclasscode
	ELSE
		SELECT * FROM
		( 	
			SELECT a.detno, a.contractcode, a.dateencoded, a.billingschedule, a.templatetype,
			billingscheduledesc = CASE a.billingschedule WHEN 1 THEN 'Monthly' WHEN 2 THEN 'Quarterly' WHEN 3 THEN 'Semi-Annual' WHEN 4 THEN 'Annual' ELSE '' END,
			a.effectivity,a.expiry, a.displaysalesportal,
			a.productcode,
			productlinecode = ISNULL(LTRIM(RTRIM(c.productlinecode)), ''),
			productline = ISNULL(LTRIM(RTRIM(c.productline)), ''),
			billclasscode = LTRIM(RTRIM(a.premiumclasscode)),
			billclassname = LTRIM(RTRIM(a.premiumclassname)), 
			billclassdesc = LTRIM(RTRIM(a.premiumclassdesc)), 
			products = (SELECT Count(premiumcode) FROM tblcompanypremiums WHERE billclassdetno = a.detno),
			benefitplan = (SELECT Count(plancode) FROM tblcompanybenefitplan WHERE classcode = a.premiumclasscode),
			encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
			a.vattype,
			vattypename = CASE  WHEN a.vattype = 1 THEN 'VATable'
								WHEN a.vattype = 2 THEN 'VAT-Exempt'
								WHEN a.vattype = 3 THEN 'Zero-Rated'
								WHEN a.vattype = 4 THEN 'Non-Vat'
								ELSE '' END,
			a.renewalclass,
			renewalclasscode = ISNULL(LTRIM(RTRIM(d.premiumclasscode)), ''),
			renewalclassname = ISNULL(LTRIM(RTRIM(d.premiumclassname)), ''),
			a.roomcategory, roomcategorycode = ISNULL(LTRIM(RTRIM(e.benefitcode)), ''),
			roomcategorydesc = ISNULL(LTRIM(RTRIM(e.description)), '')
			FROM tblcompanyclassesbilling a WITH(NOLOCK)
			OUTER APPLY (SELECT b.username FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
			OUTER APPLY (SELECT productcode, productlinecode, productline FROM tblproductlines c WITH(NOLOCK) WHERE a.productcode = c.productcode) c
			OUTER APPLY (SELECT detno, premiumclasscode, premiumclassname FROM tblcompanyclassesbilling d WITH(NOLOCK) WHERE a.renewalclass = d.detno) d
			OUTER APPLY (SELECT benefitcode, description FROM tblbenefitsa e WITH(NOLOCK) WHERE a.roomcategory = e.sacode) e
			WHERE ((a.compcode = @lcompcode)
			AND ((@lcontractcode = 0 AND a.detno <> 0) OR (@lcontractcode <> 0 AND a.contractcode = @lcontractcode))
			AND ((@ltemplatetype = 0 AND a.detno <> 0) OR (@ltemplatetype <> 0 AND a.templatetype = @ltemplatetype))
			AND ((@lproductcode = 0 AND a.detno <> 0) OR (@lproductcode <> 0 AND a.productcode = @lproductcode))
			AND ((@lvattype = 0 AND a.detno <> 0) OR (@lvattype <> 0 AND a.vattype = @lvattype))
			AND ((@lbillingschedule = 0 AND a.detno <> 0) OR (@lbillingschedule <> 0 AND a.billingschedule = @lbillingschedule))
			AND ((@lsearchkey = '' AND a.detno <> 0) OR (@lsearchkey <> '' AND a.premiumclasscode LIKE '%'+@lsearchkey+'%' OR a.premiumclassname LIKE '%'+@lsearchkey+'%'))
			AND ((@leffectivityfrom = '1/1/1900' AND a.detno <> 0) OR ((@leffectivityfrom <> '1/1/1900' AND @leffectivityto <> '1/1/1900') AND (CAST(a.effectivity AS DATE) >= CAST(@leffectivityfrom AS DATE) AND CAST(a.effectivity AS DATE) <= CAST(@leffectivityto AS DATE))))
			AND ((@lexpiryfrom = '1/1/1900' AND a.detno <> 0) OR ((@lexpiryfrom <> '1/1/1900' AND @lexpiryto <> '1/1/1900') AND (CAST(a.expiry AS DATE) >= CAST(@lexpiryfrom AS DATE) AND CAST(a.expiry AS DATE) <= CAST(@lexpiryto AS DATE)))))
		) result
		ORDER BY billclasscode
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)
END
GO

-- ---- sp_getaccountclassesv5 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getaccountclassesv5] --0, 0, 0, 0, '', '', '', '', '', 0
	-- Add the parameters for the stored procedure here
	
	@compcode			Int,
	@contractcode		Int,
	@templatetype		Int,
	@productcode		Int,
	@searchkey			Varchar(100),
	@effectivityfrom	Smalldatetime,
	@effectivityto		Smalldatetime,
	@expiryfrom			Smalldatetime,
	@expiryto			Smalldatetime,
	@encodedby			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lcompcode			Int				= @compcode,
			@lcontractcode		Int				= @contractcode,
			@ltemplatetype		Int				= @templatetype,
			@lproductcode		Int				= @productcode,
			@lsearchkey			Varchar(100)	= @searchkey,
			@leffectivityfrom	Smalldatetime	= @effectivityfrom,
			@leffectivityto		Smalldatetime	= @effectivityto,
			@lexpiryfrom		Smalldatetime	= @expiryfrom,
			@lexpiryto			Smalldatetime	= @expiryto,
			@lencodedby			Int				= @encodedby,
			@lnodata			Bit				= 0
	
	--IF (@lcompcode = 0 AND @lcontractcode = 0 AND @leffectivity = '' AND @lexpiry = '')
	--	BEGIN
	--		SET @lnodata = 1;
	--	END

	SELECT a.detno, a.compcode, a.productcode, a.templatetype, a.dentalinformation,
	templatetypename = CASE WHEN a.templatetype = 1 THEN 'Corporate'
							WHEN a.templatetype = 2 THEN 'Retail'
							ELSE '' END,
	membertype = '',
	a.agefrom, a.ageto,  
	a.agefromdep, a.agetodep,
	a.contractcode, a.parentcompcode, a.dateencoded, 
	contracteffectivity = a.effectivity,
	contractexpiry = a.expiry,
	classcode = LTRIM(RTRIM(a.classcode)),
	classname = LTRIM(RTRIM(a.classname)), 
	classdesc = LTRIM(RTRIM(a.classdesc)), 
	productlinecode = ISNULL(LTRIM(RTRIM(c.productlinecode)), 0),
	productline = ISNULL(LTRIM(RTRIM(c.productline)), ''),
	encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
	a.renewalclass,
	renewalclasscode = ISNULL(LTRIM(RTRIM(d.classcode)), ''),
	renewalclassname = ISNULL(LTRIM(RTRIM(d.classname)), ''), 
	a.ilbundled, a.topupplan, a.coveragetype,a.grandfatheredplan ,uploadsobstatus = a.withuploadsob
	FROM tblcompanyclasses a WITH(NOLOCK)
	--oUTER APPLY(SELECT membertype from tblcompanybenefitplan e where RTRIM(a.classcode) = RTRIM(e.classcode) AND a.compcode= e.compcode AND a.contractcode = e.contractcode) e
	OUTER APPLY (SELECT username,userno FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
	OUTER APPLY (SELECT productcode, productlinecode, productline FROM tblproductlines c WITH(NOLOCK) WHERE a.productcode = c.productcode) c
	OUTER APPLY (SELECT detno, classcode, classname FROM  tblcompanyclasses d WITH(NOLOCK) WHERE a.renewalclass = d.detno) d
	WHERE (((@lnodata = 1 AND a.detno = 0) OR (@lnodata = 0 AND a.detno <> 0))
	AND (a.compcode = @lcompcode)
	AND ((@lencodedby = 0 AND a.detno <> 0) OR (@lencodedby <> 0 AND a.encodedby = @lencodedby))
	AND ((@lsearchkey = '' AND a.detno <> 0) OR (@lsearchkey <> '' AND a.classcode LIKE'%'+@lsearchkey+'%' OR a.classname LIKE'%'+@lsearchkey+'%'))
	AND ((@lcontractcode = 0 AND a.detno <> 0) OR (@lcontractcode <> 0 AND a.contractcode = @lcontractcode))
	AND ((@ltemplatetype = 0 AND a.detno <> 0) OR (@ltemplatetype <> 0 AND a.templatetype = @ltemplatetype))
	AND ((@lproductcode = 0 AND a.detno <> 0) OR (@lproductcode <> 0 AND a.productcode = @lproductcode))
	AND ((@leffectivityfrom = '1/1/1900' AND a.detno <> 0) OR ((@leffectivityfrom <> '1/1/1900' AND @leffectivityto <> '1/1/1900') AND (CAST(a.effectivity AS DATE) >= CAST(@leffectivityfrom AS DATE) AND CAST(a.effectivity AS DATE) <= CAST(@leffectivityto AS DATE))))
	AND ((@lexpiryfrom = '1/1/1900' AND a.detno <> 0) OR ((@lexpiryfrom <> '1/1/1900' AND @lexpiryto <> '1/1/1900') AND (CAST(a.expiry AS DATE) >= CAST(@lexpiryfrom AS DATE) AND CAST(a.expiry AS DATE) <= CAST(@lexpiryto AS DATE)))))
	ORDER BY a.classcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getaccountclassesv6 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getaccountclassesv6] --0, 0, 0, 0, '', '', '', '', '', 0
	-- Add the parameters for the stored procedure here
	
	@compcode			Int,
	@contractcode		Int,
	@templatetype		Int,
	@productcode		Int,
	@searchkey			Varchar(100),
	@effectivityfrom	Smalldatetime,
	@effectivityto		Smalldatetime,
	@expiryfrom			Smalldatetime,
	@expiryto			Smalldatetime,
	@encodedby			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lcompcode			Int				= @compcode,
			@lcontractcode		Int				= @contractcode,
			@ltemplatetype		Int				= @templatetype,
			@lproductcode		Int				= @productcode,
			@lsearchkey			Varchar(100)	= @searchkey,
			@leffectivityfrom	Smalldatetime	= @effectivityfrom,
			@leffectivityto		Smalldatetime	= @effectivityto,
			@lexpiryfrom		Smalldatetime	= @expiryfrom,
			@lexpiryto			Smalldatetime	= @expiryto,
			@lencodedby			Int				= @encodedby,
			@lnodata			Bit				= 0
	
	--IF (@lcompcode = 0 AND @lcontractcode = 0 AND @leffectivity = '' AND @lexpiry = '')
	--	BEGIN
	--		SET @lnodata = 1;
	--	END

	SELECT a.detno, a.compcode, a.productcode, a.templatetype, a.dentalinformation, a.clinicbased,
	templatetypename = CASE WHEN a.templatetype = 1 THEN 'Corporate'
							WHEN a.templatetype = 2 THEN 'Retail'
							ELSE '' END,
	membertype = '',
	a.agefrom, a.ageto,  
	a.agefromdep, a.agetodep,
	a.contractcode, a.parentcompcode, a.dateencoded, 
	contracteffectivity = a.effectivity,
	contractexpiry = a.expiry,
	classcode = LTRIM(RTRIM(a.classcode)),
	classname = LTRIM(RTRIM(a.classname)), 
	classdesc = LTRIM(RTRIM(a.classdesc)), 
	productlinecode = ISNULL(LTRIM(RTRIM(c.productlinecode)), 0),
	productline = ISNULL(LTRIM(RTRIM(c.productline)), ''),
	encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
	a.renewalclass,
	renewalclasscode = ISNULL(LTRIM(RTRIM(d.classcode)), ''),
	renewalclassname = ISNULL(LTRIM(RTRIM(d.classname)), ''), 
	a.ilbundled, a.topupplan, a.coveragetype,a.grandfatheredplan ,uploadsobstatus = a.withuploadsob
	FROM tblcompanyclasses a WITH(NOLOCK)
	--oUTER APPLY(SELECT membertype from tblcompanybenefitplan e where RTRIM(a.classcode) = RTRIM(e.classcode) AND a.compcode= e.compcode AND a.contractcode = e.contractcode) e
	OUTER APPLY (SELECT username,userno FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
	OUTER APPLY (SELECT productcode, productlinecode, productline FROM tblproductlines c WITH(NOLOCK) WHERE a.productcode = c.productcode) c
	OUTER APPLY (SELECT detno, classcode, classname FROM  tblcompanyclasses d WITH(NOLOCK) WHERE a.renewalclass = d.detno) d
	WHERE (((@lnodata = 1 AND a.detno = 0) OR (@lnodata = 0 AND a.detno <> 0))
	AND (a.compcode = @lcompcode)
	AND ((@lencodedby = 0 AND a.detno <> 0) OR (@lencodedby <> 0 AND a.encodedby = @lencodedby))
	AND ((@lsearchkey = '' AND a.detno <> 0) OR (@lsearchkey <> '' AND a.classcode LIKE'%'+@lsearchkey+'%' OR a.classname LIKE'%'+@lsearchkey+'%'))
	AND ((@lcontractcode = 0 AND a.detno <> 0) OR (@lcontractcode <> 0 AND a.contractcode = @lcontractcode))
	AND ((@ltemplatetype = 0 AND a.detno <> 0) OR (@ltemplatetype <> 0 AND a.templatetype = @ltemplatetype))
	AND ((@lproductcode = 0 AND a.detno <> 0) OR (@lproductcode <> 0 AND a.productcode = @lproductcode))
	AND ((@leffectivityfrom = '1/1/1900' AND a.detno <> 0) OR ((@leffectivityfrom <> '1/1/1900' AND @leffectivityto <> '1/1/1900') AND (CAST(a.effectivity AS DATE) >= CAST(@leffectivityfrom AS DATE) AND CAST(a.effectivity AS DATE) <= CAST(@leffectivityto AS DATE))))
	AND ((@lexpiryfrom = '1/1/1900' AND a.detno <> 0) OR ((@lexpiryfrom <> '1/1/1900' AND @lexpiryto <> '1/1/1900') AND (CAST(a.expiry AS DATE) >= CAST(@lexpiryfrom AS DATE) AND CAST(a.expiry AS DATE) <= CAST(@lexpiryto AS DATE)))))
	ORDER BY a.classcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getaccountcontractyearsv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getaccountcontractyearsv2] --70614
	-- Add the parameters for the stored procedure here
	
	@compcode	Int

AS
BEGIN
	-- SET NOCOUNT WITH(NOLOCK) WHERE added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lcompcode	Int	 = @compcode

	SELECT a.contractcode, a.compcode, a.contractyearfrom, a.contractyearto, a.initial, a.preterm,
	a.effectivity, a.expiry, a.dateposted, a.active, a.extensionfrom, a.extensionto, a.extension, 
	a.initialmadtype, a.renewalmadtype, a.initialmembercount, a.renewalmembercount, a.initialtotalamount, 
	a.renewaltotalamount, a.calendardays, a.initialcreditterm, a.renewalcreditterm, a.modalcreditterm,
	remarks = LTRIM(RTRIM(a.remarks)), a.extendmonthly, a.extendquarterly, a.extendsemiannual,
	postedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
	uploadsobstatus = a.withuploadsob, absfilename = ISNULL(LTRIM(RTRIM(a.absfilename)), ''),
	modalextcreditterm = ISNULL(a.modalextcreditterm, 1/1/1900),
	modalextcredittermquarterly = ISNULL(a.modalextcredittermquarterly, 1/1/1900),
	modalextcredittermsemiannual = ISNULL(a.modalextcredittermsemiannual, 1/1/1900),
	a.renewalcontractcode
	FROM tblcompanycontractyears a WITH(NOLOCK)
	OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.postedby = b.userno) b
	WHERE a.compcode = @lcompcode
	ORDER BY a.effectivity DESC
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getaccountcontractyearsv3 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getaccountcontractyearsv3] --70614
	-- Add the parameters for the stored procedure here
	
	@compcode	Int

AS
BEGIN
	-- SET NOCOUNT WITH(NOLOCK) WHERE added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lcompcode	Int	 = @compcode

	SELECT a.contractcode, a.compcode, a.contractyearfrom, a.contractyearto, a.initial, a.preterm,
	a.effectivity, a.expiry, a.dateposted, a.active, a.extensionfrom, a.extensionto, a.extension, 
	a.initialmadtype, a.renewalmadtype, a.initialmembercount, a.renewalmembercount, a.initialtotalamount, 
	a.renewaltotalamount, a.calendardays, a.initialcreditterm, a.renewalcreditterm, a.modalcreditterm,
	remarks = LTRIM(RTRIM(a.remarks)), a.extendmonthly, a.extendquarterly, a.extendsemiannual, a.autorenewal,
	postedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
	uploadsobstatus = a.withuploadsob, absfilename = ISNULL(LTRIM(RTRIM(a.absfilename)), ''),
	modalextcreditterm = ISNULL(a.modalextcreditterm, 1/1/1900),
	modalextcredittermquarterly = ISNULL(a.modalextcredittermquarterly, 1/1/1900),
	modalextcredittermsemiannual = ISNULL(a.modalextcredittermsemiannual, 1/1/1900),
	a.renewalcontractcode
	FROM tblcompanycontractyears a WITH(NOLOCK)
	OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.postedby = b.userno) b
	WHERE a.compcode = @lcompcode
	ORDER BY a.effectivity DESC
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getaccountdetailsv7 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getaccountdetailsv7] --554

	@compcode Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lcompcode Int = @compcode

	EXEC sp_opensymmetric

	SELECT a.compcode, a.companytype, a.companysetup, a.productcode, a.vattype, a.dateenrolled, a.autore, a.enhancedencryption, a.restrictdependentmobile, a.maxcpddependent, a.maxvpddependent,
	a.billingcompcode, a.effectivity, a.expiry, a.coveredfrom, a.coveredto, a.statuscode, a.parentcompcode, a.encodedby,
	a.dateencoded, a.manualcontractno, a.billingschedule, a.inactivedate, a.datesuspended, a.revolvingfund, a.citycode, a.provincecode, a.zipcode,
	a.agentno, a.cwtax, a.restrictmobile, a.roundingoff, a.memberpremium, 
	a.asoadminfeetype, a.asoadminfee, a.asoservicefeetype, a.asoservicefee,
	a.allowmemberportal, a.memberportalaccessfrom, a.memberportalaccessto, a.telemedicine,
	contractno = LTRIM(RTRIM(a.contractno)), 
	companyname = LTRIM(RTRIM(dbo.decrypt(a.companyname))), 
	--companyname = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.ldflog, 0), ''))),
	initial = LTRIM(RTRIM(a.initial)), 
	telephone = LTRIM(RTRIM(a.telephone)), 
	fax = LTRIM(RTRIM(a.fax)), 
	tinno = LTRIM(RTRIM(a.tinno)), 
	streetaddress = LTRIM(RTRIM(a.streetaddress)),				 
	website = LTRIM(RTRIM(a.website)), a.branch, 
	accountcode = LTRIM(RTRIM(a.accountcode)), 
	premiumcaption = LTRIM(RTRIM(a.premiumcaption)),
	roundingoffname = CASE a.roundingoff 
	WHEN 1 THEN 'Standard with rounding off' 
	WHEN 2 THEN 'No rounding off the basic premium and rider' 
	WHEN 3 THEN 'Rounding off the basic premium and no rounding off the rider' ELSE '' END, 
	vattypedesc = CASE a.vattype WHEN 1 THEN 'VATABLE' WHEN 2 THEN 'VAT-EXEMPT' WHEN 3 THEN 'ZERO-RATED' WHEN 4 THEN 'NON-VAT' ELSE '' END,
	memberpremiumdesc = CASE a.memberpremium WHEN 1 THEN 'INCLUSIVE RIDER' WHEN 2 THEN 'EXCLUSIVE RIDER' ELSE '' END,
	statusname = ISNULL(LTRIM(RTRIM(b.statusname)),''), 
	statusintial = ISNULL(LTRIM(RTRIM(b.initial)),''), 
	cityname = ISNULL(LTRIM(RTRIM(c.locationname)),''), 
	provincename = ISNULL(LTRIM(RTRIM(d.locationname)),''),  
	encodedbyname = ISNULL(LTRIM(RTRIM(e.username)),''),
	contractcode = ISNULL(f.contractcode, 0),  
	contracteffectivity = ISNULL(f.effectivity, 1/1/1900 ), 
	contractexpiry = ISNULL(f.expiry, 1/1/1900), 
	contractexpiryextension = ISNULL(f.extensionto, 1/1/1900), 
	companyproduct = ISNULL(LTRIM(RTRIM(g.recordcode)),''), 
	companytypeno = ISNULL(g.recordno, 0), 
	companytypedesc = ISNULL(LTRIM(RTRIM(g.description)),''), 
	a.accountgroup,accountgroupdesc = ISNULL(LTRIM(RTRIM(n.description)),''), 
	motheraccount = ISNULL(LTRIM(RTRIM(i.companyname)),''), 
	branchname = ISNULL(LTRIM(RTRIM(j.locationname)), ''), 
	asoadminfeetypedesc = ISNULL(LTRIM(RTRIM(k.description)), ''), 
	asoservicefeetypedesc = ISNULL(LTRIM(RTRIM(l.description)), ''),
	contractinitial = ISNULL(f.initial, 0),
	calendardaysdes = IIF(f.calendardays = 1, 'CALENDAR DAYS', 'WORKING DAYS'),
	modalcreditterm = ISNULL(f.modalcreditterm, 0),
	creditterm = IIF(f.initial = 1, ISNULL(f.initialcreditterm, 0), ISNULL(f.renewalcreditterm, 0)),	
	madcount = IIF(f.initial = 1, ISNULL(f.initialmembercount, 0), ISNULL(f.renewalmembercount, 0)),
	madtype = IIF(f.initial = 1, CASE f.initialmadtype WHEN 1 THEN 'PRINCIPAL ONLY' WHEN 2 THEN 'DEPENDENT ONLY' WHEN 3 THEN 'BOTH' ELSE '' END, CASE f.renewalmadtype WHEN 1 THEN 'PRINCIPAL ONLY' WHEN 2 THEN 'DEPENDENT ONLY' WHEN 3 THEN 'BOTH' ELSE '' END),
	madtotalamount = ISNULL(IIF(f.initial = 1, f.initialtotalamount, f.renewaltotalamount), 0.00),
	a.restrictautoloaapproval, a.wtaxno, a.wtax,
	wtaxcode = ISNULL(LTRIM(RTRIM(m.wtaxcode)), '')
	FROM tblcompany a WITH(NOLOCK)
	OUTER APPLY (SELECT statusname, initial FROM tblstatus b WITH(NOLOCK) WHERE a.statuscode = b.statusno AND b.statusfor = 'CORPORATE') b
	OUTER APPLY (SELECT locationname FROM tbllocations c WITH(NOLOCK) WHERE a.citycode = c.locationcode) c
	OUTER APPLY (SELECT locationname FROM tbllocations d WITH(NOLOCK) WHERE a.provincecode = d.locationcode) d 
	OUTER APPLY (SELECT username FROM tblusers e WITH(NOLOCK) WHERE a.encodedby = e.userno) e
	OUTER APPLY (SELECT initial, effectivity, expiry, extensionto, contractcode, calendardays, initialcreditterm, renewalcreditterm, modalcreditterm, initialmembercount, renewalmembercount, initialmadtype,  renewalmadtype,
	initialtotalamount, renewaltotalamount FROM tblcompanycontractyears f WITH(NOLOCK) WHERE a.compcode = f.compcode AND a.effectivity = f.effectivity) f
	OUTER APPLY (SELECT recordcode, recordno, description FROM tblgentables g WITH(NOLOCK) WHERE a.companytype = g.detno AND g.tablename = 'COMPANY TYPE') g
	OUTER APPLY (SELECT companyname FROM tblcompany i WITH(NOLOCK) WHERE a.parentcompcode = i.compcode) i
	OUTER APPLY (SELECT locationname FROM tbllocations j WITH(NOLOCK) WHERE a.branch = j.locationcode AND j.locationtype = 'BRANCH') j
	OUTER APPLY (SELECT description FROM tblgentables k WITH(NOLOCK) WHERE a.asoadminfeetype = k.recordno AND k.tablename = 'ASO ADMIN FEE') k
	OUTER APPLY (SELECT description FROM tblgentables l WITH(NOLOCK) WHERE a.asoservicefeetype = l.recordno AND l.tablename = 'ASO SERVICE FEE') l
	OUTER APPLY (SELECT wtaxcode FROM tblwtaxrates m WITH(NOLOCK) WHERE a.wtaxno = m.wtaxno) m
	OUTER APPLY (SELECT recordcode, recordno, description FROM tblgentables n WITH(NOLOCK) WHERE a.accountgroup = n.detno AND n.tablename = 'ACCOUNT GROUPS') n
	WHERE a.compcode = @lcompcode
	OPTION(RECOMPILE)

	EXEC sp_closesymmetric
END

GO

-- ---- sp_getaccountfundsetupjournal ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getaccountfundsetupjournal]

	@funddetno Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lfunddetno Int = @funddetno

	SELECT a.detno, a.funddetno, a.compcode, 
	description = LTRIM(RTRIM(a.description)),
	a.datecreated, a.createdby,
	createdbyname = ISNULL(LTRIM(RTRIM(b.username)), '')
	FROM tblaccountfundsetupjournal a WITH(NOLOCK)
	OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.createdby = b.userno) b
	WHERE a.funddetno = @lfunddetno
	ORDER BY a.datecreated DESC
	OPTION(RECOMPILE)

END

GO

-- ---- sp_getaccountsettingspremium ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getaccountsettingspremium]
	-- Add the parameters for the stored procedure here
	
	@compcode			Int,
	@billclassdetno		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lcompcode			Int				= @compcode,
			@lbillclassdetno	Int				= @billclassdetno

	SELECT a.detno, a.compcode, a.billclassdetno,
	a.premiumsetup, premiumsetupname = CASE WHEN a.premiumsetup = 1 THEN 'Standard (Modal Factor)'
											WHEN a.premiumsetup = 2 THEN 'Non-Standard (365 days)'
											ELSE '' END,
	a.refundsetup, refundsetupname = CASE WHEN a.refundsetup = 1 THEN 'Standard'
										  WHEN a.refundsetup = 2 THEN 'Non-Standard'
										  ELSE '' END,
	notmorethan15 = ISNULL(LTRIM(RTRIM(a.notmorethan15)), 0),
	morethan15 = ISNULL(LTRIM(RTRIM(a.morethan15)), 0),
	morethan1month = ISNULL(LTRIM(RTRIM(a.morethan1month)), 0),
	morethan2months = ISNULL(LTRIM(RTRIM(a.morethan2months)), 0)
	FROM tblsettingspremium a WITH(NOLOCK)
	WHERE a.compcode = @lcompcode AND a.billclassdetno = @lbillclassdetno
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getaccountvpdclasses ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getaccountvpdclasses] --'', '001', 262, 253, 0, 0
	-- Add the parameters for the stored procedure here
	
	
	@benefitsearch	Varchar(100),
	@parentclassdetno Int,
	@contractcode	Int,
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT WITH(NOLOCK) WHERE added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lbenefitsearch		Varchar(100)	= @benefitsearch,
			@lparentclassdetno	Int				= @parentclassdetno,
			@lcontractcode		Int				= @contractcode,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr

	SELECT @rowcount = COUNT(1)
	FROM tblcompanyclasses a WITH(NOLOCK)
	WHERE a.coveragetype = 1 AND contractcode = @lcontractcode 
	AND a.detno NOT IN (SELECT classdetno FROM tblcompanyclassesvpdlink b WITH(NOLOCK) WHERE b.parentclassdetno = @lparentclassdetno)
	AND ((@lbenefitsearch = '' AND a.detno <> 0) OR (@lbenefitsearch <> '' AND a.classcode LIKE'%'+@lbenefitsearch+'%' OR a.classname LIKE'%'+@lbenefitsearch+'%'))
	OPTION(RECOMPILE)

    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		(
			SELECT a.detno, a.classcode, a.classname
			FROM tblcompanyclasses a WITH(NOLOCK)
			WHERE a.coveragetype = 1 AND contractcode = @lcontractcode 
			AND a.detno NOT IN (SELECT classdetno FROM tblcompanyclassesvpdlink b WITH(NOLOCK) WHERE b.parentclassdetno = @lparentclassdetno)
			AND ((@lbenefitsearch = '' AND a.detno <> 0) OR (@lbenefitsearch <> '' AND a.classcode LIKE'%'+@lbenefitsearch+'%' OR a.classname LIKE'%'+@lbenefitsearch+'%'))
		) result
		ORDER BY classcode
	ELSE
		SELECT * FROM
		(
			SELECT a.detno, a.classcode, a.classname
			FROM tblcompanyclasses a WITH(NOLOCK)
			WHERE a.coveragetype = 1 AND contractcode = @lcontractcode 
			AND a.detno NOT IN (SELECT classdetno FROM tblcompanyclassesvpdlink b WITH(NOLOCK) WHERE b.parentclassdetno = @lparentclassdetno)
			AND ((@lbenefitsearch = '' AND a.detno <> 0) OR (@lbenefitsearch <> '' AND a.classcode LIKE'%'+@lbenefitsearch+'%' OR a.classname LIKE'%'+@lbenefitsearch+'%'))
		) result
		ORDER BY classcode
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE) 


END
GO

-- ---- sp_getaccountvpdlinkclasses ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getaccountvpdlinkclasses] --'', '001', 262, 253, 0, 0
	-- Add the parameters for the stored procedure here
	
	
	@benefitsearch	Varchar(100),
	@parentclassdetno		Int,
	@contractcode	Int,
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT WITH(NOLOCK) WHERE added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lbenefitsearch		Varchar(100)	= @benefitsearch,
			@lcontractcode		Int				= @contractcode,
			@lparentclassdetno	Int				= @parentclassdetno,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr

	SELECT @rowcount = COUNT(1)
	FROM tblcompanyclassesvpdlink a WITH(NOLOCK)
	OUTER APPLY (SELECT classcode, classname FROM tblcompanyclasses b WITH(NOLOCK) WHERE a.classdetno = b.detno ) b
	OUTER APPLY (SELECT username,userno FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c
	WHERE a.parentclassdetno = @lparentclassdetno
	AND ((@lbenefitsearch = '' AND a.detno <> 0) OR (@lbenefitsearch <> '' AND b.classcode LIKE'%'+@lbenefitsearch+'%' OR b.classname LIKE'%'+@lbenefitsearch+'%'))
	OPTION(RECOMPILE)

    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		(
			SELECT  a.detno, a.classdetno, a.parentclassdetno, 
			classcode = ISNULL(b.classcode, ''), 
			classname = ISNULL(b.classname, ''),
					encodedbyname = ISNULL(c.username,''),
					dateencoded = ISNULL(a.dateencoded, CAST('1/1/1900' AS smalldatetime))
			FROM tblcompanyclassesvpdlink a WITH(NOLOCK)
			OUTER APPLY (SELECT classcode, classname FROM tblcompanyclasses b WITH(NOLOCK) WHERE a.classdetno = b.detno ) b
			OUTER APPLY (SELECT username,userno FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c
			WHERE a.parentclassdetno = @lparentclassdetno
			AND ((@lbenefitsearch = '' AND a.detno <> 0) OR (@lbenefitsearch <> '' AND b.classcode LIKE'%'+@lbenefitsearch+'%' OR b.classname LIKE'%'+@lbenefitsearch+'%'))
		) result
		ORDER BY classcode
	ELSE
		SELECT * FROM
		(
			SELECT  a.detno, a.classdetno, a.parentclassdetno, 
			classcode = ISNULL(b.classcode, ''), 
			classname = ISNULL(b.classname, ''),
					encodedbyname = ISNULL(c.username,''),
					dateencoded = ISNULL(a.dateencoded, CAST('1/1/1900' AS smalldatetime))
			FROM tblcompanyclassesvpdlink a WITH(NOLOCK)
			OUTER APPLY (SELECT classcode, classname FROM tblcompanyclasses b WITH(NOLOCK) WHERE a.classdetno = b.detno ) b
			OUTER APPLY (SELECT username,userno FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c
			WHERE a.parentclassdetno = @lparentclassdetno
			AND ((@lbenefitsearch = '' AND a.detno <> 0) OR (@lbenefitsearch <> '' AND b.classcode LIKE'%'+@lbenefitsearch+'%' OR b.classname LIKE'%'+@lbenefitsearch+'%'))
		) result
		ORDER BY classcode
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE) 


END
GO

-- ---- sp_getapprovalcodebatchbreakdownledger ----
CREATE   PROCEDURE [dbo].[sp_getapprovalcodebatchbreakdownledger] --12, '', '', -1, 1, 20
	-- Add the parameters for the stored procedure here
	@batchcode			Int,
	@membersearch		Varchar(100),
	@approvalcode		Varchar(20),
	@withfindings		Int,
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lbatchcode			Int				= @batchcode,
			@lmembersearch		Varchar(100)	= @membersearch,
			@lapprovalcode		Varchar(20)		= @approvalcode,
			@lwithfindings		Int				= @withfindings,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lnodata			Tinyint			= 0;

	EXEC sp_opensymmetric

	SELECT @rowcount = COUNT(1)
	FROM tblbatchloamappingdetails a WITH(NOLOCK)
	OUTER APPLY (SELECT membername FROM  tblmembers b WITH(NOLOCK) WHERE a.memberno = b.memberno AND a.memberno <> '' ) b 
	WHERE a.batchcode = @lbatchcode
		AND ((@lmembersearch = '' AND a.detno <> 0) OR (@lmembersearch <> '' AND a.memberno LIKE '%' + @lmembersearch + '%')
												  OR (@lmembersearch <> '' AND dbo.Decrypt(b.membername) LIKE '%' + @lmembersearch + '%'))
		AND ((@lapprovalcode = '' AND a.detno <> 0) OR (@lapprovalcode <> '' AND a.approvalcode LIKE '%' + @lapprovalcode + '%'))
		AND ((@lwithfindings = -1 AND a.detno <> 0) OR (@lwithfindings = 0 AND a.failedremarks = '')
													OR (@lwithfindings = 1 AND a.failedremarks <> ''))
	If @pageno <= 0 or @rowctr <= 0
		BEGIN
			SELECT a.detno, a.memberno, a.approvalcode, a.failedremarks,
			membername = ISNULL(dbo.Decrypt(b.membername), '')
			FROM tblbatchloamappingdetails a WITH(NOLOCK)
			OUTER APPLY (SELECT membername FROM  tblmembers b WITH(NOLOCK) WHERE a.memberno = b.memberno AND a.memberno <> '') b 
			WHERE a.batchcode = @lbatchcode
				AND ((@lmembersearch = '' AND a.detno <> 0) OR (@lmembersearch <> '' AND a.memberno LIKE '%' + @lmembersearch + '%')
														  OR (@lmembersearch <> '' AND dbo.Decrypt(b.membername) LIKE '%' + @lmembersearch + '%'))
				AND ((@lapprovalcode = '' AND a.detno <> 0) OR (@lapprovalcode <> '' AND a.approvalcode LIKE '%' + @lapprovalcode + '%'))
				AND ((@lwithfindings = -1 AND a.detno <> 0) OR (@lwithfindings = 0 AND a.failedremarks = '')
															OR (@lwithfindings = 1 AND a.failedremarks <> ''))
			ORDER BY membername DESC
		END
	ELSE
		BEGIN
			SELECT a.detno, a.memberno, a.approvalcode, a.failedremarks,
			membername = ISNULL(dbo.Decrypt(b.membername), '')
			FROM tblbatchloamappingdetails a WITH(NOLOCK)
			OUTER APPLY (SELECT membername FROM  tblmembers b WITH(NOLOCK) WHERE a.memberno = b.memberno AND a.memberno <> '') b 
			WHERE a.batchcode = @lbatchcode
				AND ((@lmembersearch = '' AND a.detno <> 0) OR (@lmembersearch <> '' AND a.memberno LIKE '%' + @lmembersearch + '%')
														  OR (@lmembersearch <> '' AND dbo.Decrypt(b.membername) LIKE '%' + @lmembersearch + '%'))
				AND ((@lapprovalcode = '' AND a.detno <> 0) OR (@lapprovalcode <> '' AND a.approvalcode LIKE '%' + @lapprovalcode + '%'))
				AND ((@lwithfindings = -1 AND a.detno <> 0) OR (@lwithfindings = 0 AND a.failedremarks = '')
															OR (@lwithfindings = 1 AND a.failedremarks <> ''))
			ORDER BY membername DESC
			OFFSET ((@lpageno - 1) * @lrowctr) ROWS
			FETCH NEXT @lrowctr ROWS ONLY

		END
	EXEC sp_closesymmetric
END

GO

-- ---- sp_getapprovalcodemappingledger ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE     PROCEDURE [dbo].[sp_getapprovalcodemappingledger] 

	@batchno			Varchar(50),
	@dateimportedfrom	Smalldatetime,
	@dateimportedto		Smalldatetime,
	@importedby			Varchar(100),
	@statuscode			Int,
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lbatchno			Varchar(50)		= @batchno,
			@ldateimportedfrom	Smalldatetime	= @dateimportedfrom,
			@ldateimportedto	Smalldatetime	= @dateimportedto,
			@limportedby		Varchar(100)	= @importedby,
			@lstatuscode		Int				= @statuscode,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lnodata			Tinyint

	EXEC sp_opensymmetric

	SELECT @rowcount = COUNT(1)
	FROM tblbatchloamapping a WITH(NOLOCK)
	OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.uploadedby = c.userno) c
	WHERE((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%'+LTRIM(RTRIM(@lbatchno))+'%'))
	AND ((@ldateimportedfrom = '1/1/1900' AND a.batchcode <> 0) OR ((@ldateimportedfrom <> '1/1/1900' AND @ldateimportedto <> '1/1/1900')
			AND (CAST(a.dateuploaded  AS DATE) >= CAST(@ldateimportedfrom AS DATE) AND CAST(a.dateuploaded  AS DATE) <= CAST(@ldateimportedto AS DATE))))
	--AND ((@lstatuscode = '' AND a.batchcode <> 0) OR (@lstatuscode <> '' AND  CHARINDEX('_'+ CAST(a.statuscode AS VARCHAR(10)) +'_' ,@lstatuscode) > 0 ))
	AND ((@lstatuscode = 0 AND a.batchcode <> 0) OR (@lstatuscode <> 0 AND a.statuscode = @lstatuscode))
	--AND ((@limportedby = 0 AND a.batchcode <> 0) OR (@limportedby <> 0 AND a.uploadedby = @limportedby))
	AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
	OPTION(RECOMPILE)


    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		( 	
			SELECT a.batchcode, a.dateuploaded, a.batchno, a.datestarted, a.datefinished, a.duration, 
			filename = a.loamappingfilename,
			a.uploadtype, a.remarks, a.uploadcount,
			a.statuscode, statusname = ISNULL(b.statusname, ''),
			a.uploadedby, uploadedbyname = ISNULL(c.username, '')
			FROM tblbatchloamapping a WITH(NOLOCK)
			OUTER APPLY (SELECT statusname, initial FROM tblstatus b WITH(NOLOCK) WHERE a.statuscode = b.statusno AND b.statusfor = 'APPROVAL CODE MAP') b
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.uploadedby = c.userno) c
			WHERE((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%'+LTRIM(RTRIM(@lbatchno))+'%'))
			AND ((@ldateimportedfrom = '1/1/1900' AND a.batchcode <> 0) OR ((@ldateimportedfrom <> '1/1/1900' AND @ldateimportedto <> '1/1/1900')
					AND (CAST(a.dateuploaded  AS DATE) >= CAST(@ldateimportedfrom AS DATE) AND CAST(a.dateuploaded  AS DATE) <= CAST(@ldateimportedto AS DATE))))
			--AND ((@lstatuscode = '' AND a.batchcode <> 0) OR (@lstatuscode <> '' AND  CHARINDEX('_'+ CAST(a.statuscode AS VARCHAR(10)) +'_' ,@lstatuscode) > 0 ))
			AND ((@lstatuscode = 0 AND a.batchcode <> 0) OR (@lstatuscode <> 0 AND a.statuscode = @lstatuscode))
			--AND ((@limportedby = 0 AND a.batchcode <> 0) OR (@limportedby <> 0 AND a.uploadedby = @limportedby))
			AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
		) result
		ORDER BY dateuploaded 
	ELSE
		SELECT * FROM
		( 	
			SELECT a.batchcode, a.dateuploaded, a.batchno, a.datestarted, a.datefinished, a.duration, 
			filename = a.loamappingfilename,
			a.uploadtype, a.remarks, a.uploadcount,
			a.statuscode, statusname = ISNULL(b.statusname, ''),
			a.uploadedby, uploadedbyname = ISNULL(c.username, '')
			FROM tblbatchloamapping a WITH(NOLOCK)
			OUTER APPLY (SELECT statusname, initial FROM tblstatus b WITH(NOLOCK) WHERE a.statuscode = b.statusno AND b.statusfor = 'APPROVAL CODE MAP') b
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.uploadedby = c.userno) c
			WHERE((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%'+LTRIM(RTRIM(@lbatchno))+'%'))
			AND ((@ldateimportedfrom = '1/1/1900' AND a.batchcode <> 0) OR ((@ldateimportedfrom <> '1/1/1900' AND @ldateimportedto <> '1/1/1900')
					AND (CAST(a.dateuploaded  AS DATE) >= CAST(@ldateimportedfrom AS DATE) AND CAST(a.dateuploaded  AS DATE) <= CAST(@ldateimportedto AS DATE))))
			--AND ((@lstatuscode = '' AND a.batchcode <> 0) OR (@lstatuscode <> '' AND  CHARINDEX('_'+ CAST(a.statuscode AS VARCHAR(10)) +'_' ,@lstatuscode) > 0 ))
			AND ((@lstatuscode = 0 AND a.batchcode <> 0) OR (@lstatuscode <> 0 AND a.statuscode = @lstatuscode))
			--AND ((@limportedby = 0 AND a.batchcode <> 0) OR (@limportedby <> 0 AND a.uploadedby = @limportedby))
			AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
		) result
		ORDER BY dateuploaded 
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)
	
	EXEC sp_closesymmetric
END

GO

-- ---- sp_getasoaccountfund ----
CREATE PROCEDURE [dbo].[sp_getasoaccountfund] 
	-- Add the parameters for the stored procedure here
	
	@fundcode			Varchar(50),
	@fundescription		Varchar(100),	
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lfundcode			Varchar(50)		= @fundcode,
			@lfundescription	Varchar(100)	= @fundescription,			
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lnodata			Tinyint			= 0

	IF (@lfundcode = '' AND @lfundescription = '')
		BEGIN
			SET @lnodata = 1;
		END
	
	SELECT @rowcount = COUNT(1)
	FROM tblasoaccountfunds a WITH(NOLOCK)
	WHERE (
		  ((@lnodata = 1 AND a.fundno = 0) OR (@lnodata = 0 AND a.fundno <> 0))
		  AND ((@lfundcode = '' AND a.fundno <> 0) OR (@lfundcode <> '' AND a.fundcode LIKE '%'+@lfundcode+'%'))
		  AND ((@lfundescription = '' AND a.fundno <> 0) OR (@lfundescription <> '' AND a.description LIKE '%'+@lfundescription+'%'))
	)
	OPTION(RECOMPILE)

	IF @lpageno <= 0 or @lrowctr <= 0
		SELECT * FROM
		(
			SELECT a.fundno, 
			fundcode = LTRIM(RTRIM(a.fundcode)), 
			funddescription = LTRIM(RTRIM(a.description)), 
			encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
			a.encodedby, a.dateencoded 
			FROM tblasoaccountfunds a WITH(NOLOCK)
			OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
			WHERE (
				  ((@lnodata = 1 AND a.fundno = 0) OR (@lnodata = 0 AND a.fundno <> 0))
				  AND ((@lfundcode = '' AND a.fundno <> 0) OR (@lfundcode <> '' AND a.fundcode LIKE '%'+@lfundcode+'%'))
				  AND ((@lfundescription = '' AND a.fundno <> 0) OR (@lfundescription <> '' AND a.description LIKE '%'+@lfundescription+'%'))
			)
		) result
		ORDER BY dateencoded desc
	ELSE
		SELECT * FROM
		(
			SELECT a.fundno, 
			fundcode = LTRIM(RTRIM(a.fundcode)), 
			funddescription = LTRIM(RTRIM(a.description)), 
			encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
			a.encodedby, a.dateencoded 
			FROM tblasoaccountfunds a WITH(NOLOCK)
			OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
			WHERE (
				  ((@lnodata = 1 AND a.fundno = 0) OR (@lnodata = 0 AND a.fundno <> 0))
				  AND ((@lfundcode = '' AND a.fundno <> 0) OR (@lfundcode <> '' AND a.fundcode LIKE '%'+@lfundcode+'%'))
				  AND ((@lfundescription = '' AND a.fundno <> 0) OR (@lfundescription <> '' AND a.description LIKE '%'+@lfundescription+'%'))
			)
		) result
		ORDER BY dateencoded desc
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)
END
GO

-- ---- sp_getassigndcfmembers ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getassigndcfmembers]
	-- Add the parameters for the stored procedure here
	
	@lastname			Varchar(100),
	@firstname			Varchar(100),
	@memberno			Varchar(50),
	@productcode		Int,
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @llastname			Varchar(100)	= @lastname,
			@lfirstname			Varchar(100)	= @firstname,
			@lmemberno			Varchar(50)		= @memberno,
			@lproductcode		Int				= @productcode,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lnodata			Bit				= 0

	IF (@llastname = '' AND @lfirstname = '' AND @lmemberno = '' AND @lproductcode = 0)
		BEGIN
			SET @lnodata = 1;
		END

	EXEC sp_opensymmetric

	--IF OBJECT_ID('#count') IS NOT NULL 
	--BEGIN 
	--	DROP TABLE #count
	--END
	
	--CREATE TABLE #count
	--(
	--totalctr int NOT NULL
	--)

	--insert into #count (totalctr)
	--SELECT COUNT(1)

	SELECT @rowcount = COUNT(1)
	FROM tblmembers a WITH(NOLOCK)
	OUTER APPLY (SELECT productcode FROM tblcompanyclasses b WITH(NOLOCK) WHERE b.contractcode = 0 AND b.compcode = 0 AND b.classcode = a.benefitclass AND b.templatetype = 2) AS b
	WHERE (((@lnodata = 1 AND a.membercode <> 0) OR (@lnodata = 0 AND a.membercode <> 0 AND a.compcode = 0))
	AND ((@llastname = '' AND a.membercode <> 0) OR (@llastname <> '' AND dbo.decodercontains(a.llog, 0) LIKE '%'+LTRIM(RTRIM(@llastname))+'%'))
	AND ((@lfirstname = '' AND a.membercode <> 0) OR (@lfirstname <> '' AND dbo.decodercontains(a.flog, 0) LIKE '%'+LTRIM(RTRIM(@lfirstname))+'%'))
	AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+LTRIM(RTRIM(@lmemberno))+'%'))
	AND ((@lproductcode = 0 AND a.membercode <> 0) OR (@lproductcode <> 0 AND b.productcode = @lproductcode)))
	OPTION(RECOMPILE)

	If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		( 	
			SELECT a.rowmarker, a.membercode,
			memberno = ISNULL(a.memberno, ''),
			membername = LTRIM(RTRIM(ISNULL(dbo.decrypt(a.membername), ''))),
			productcode = ISNULL(b.productcode, 0),
			productline = ISNULL(c.productline, ''),
			dcftemplate = ISNULL(a.dcftemplate, '')
			FROM tblmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT productcode FROM tblcompanyclasses b WITH(NOLOCK) WHERE b.contractcode = 0 AND b.compcode = 0 AND b.classcode = a.benefitclass AND b.templatetype = 2) AS b
			OUTER APPLY (SELECT productline FROM tblproductlines c WITH(NOLOCK) WHERE c.productcode = b.productcode) c
			WHERE (((@lnodata = 1 AND a.membercode <> 0) OR (@lnodata = 0 AND a.membercode <> 0 AND a.compcode = 0))
			AND ((@llastname = '' AND a.membercode <> 0) OR (@llastname <> '' AND dbo.decodercontains(a.llog, 0) LIKE '%'+LTRIM(RTRIM(@llastname))+'%'))
			AND ((@lfirstname = '' AND a.membercode <> 0) OR (@lfirstname <> '' AND dbo.decodercontains(a.flog, 0) LIKE '%'+LTRIM(RTRIM(@lfirstname))+'%'))
			AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+LTRIM(RTRIM(@lmemberno))+'%'))
			AND ((@lproductcode = 0 AND a.membercode <> 0) OR (@lproductcode <> 0 AND b.productcode = @lproductcode)))
		) result
		ORDER BY membername
	ELSE
		SELECT * FROM
		( 	
			SELECT a.rowmarker, a.membercode,
			memberno = ISNULL(a.memberno, ''),
			membername = LTRIM(RTRIM(ISNULL(dbo.decrypt(a.membername), ''))),
			productcode = ISNULL(b.productcode, 0),
			productline = ISNULL(c.productline, ''),
			dcftemplate = ISNULL(a.dcftemplate, '')
			FROM tblmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT productcode FROM tblcompanyclasses b WITH(NOLOCK) WHERE b.contractcode = 0 AND b.compcode = 0 AND b.classcode = a.benefitclass AND b.templatetype = 2) AS b
			OUTER APPLY (SELECT productline FROM tblproductlines c WITH(NOLOCK) WHERE c.productcode = b.productcode) c
			WHERE (((@lnodata = 1 AND a.membercode <> 0) OR (@lnodata = 0 AND a.membercode <> 0 AND a.compcode = 0))
			AND ((@llastname = '' AND a.membercode <> 0) OR (@llastname <> '' AND dbo.decodercontains(a.llog, 0) LIKE '%'+LTRIM(RTRIM(@llastname))+'%'))
			AND ((@lfirstname = '' AND a.membercode <> 0) OR (@lfirstname <> '' AND dbo.decodercontains(a.flog, 0) LIKE '%'+LTRIM(RTRIM(@lfirstname))+'%'))
			AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+LTRIM(RTRIM(@lmemberno))+'%'))
			AND ((@lproductcode = 0 AND a.membercode <> 0) OR (@lproductcode <> 0 AND b.productcode = @lproductcode)))
		) result
		ORDER BY membername
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)

	EXEC sp_closesymmetric
END


GO

-- ---- sp_getauthoritytodeductsettingsv2 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getauthoritytodeductsettingsv2] 
	-- Add the parameters for the stored procedure here
	
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	--DEClARE @lcompcode	Int		= @compcode,
	--		@lstatus	TinyInt	= @status

    SELECT a.detno, a.compcode, a.title, a.body, a.confirmationtext, a.datecreated, a.atdtext,
	companyname = ISNULL(dbo.decoder(b.ldflog,0), ''),
	contractno = ISNULL(b.contractno, ''),
	encodedbyname = ISNULL(c.username, '')
	FROM tblauthoritytodeductsettings a WITH(NOLOCK)
	OUTER APPLY (SELECT ldflog, contractno FROM tblcompany b WITH(NOLOCK) WHERE a.compcode = b.compcode) b
	OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.createdby = c.userno) c
	ORDER BY a.datecreated DESC
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getbatchapeapprovalcodes ----
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getbatchapeapprovalcodes] --11770,1122,1,20
	-- Add the parameters for the stored procedure here

	@compcode		Int,
	@providercode	Int,
	@utildatefrom	Smalldatetime,
	@utildateto		Smalldatetime,
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lcompcode			Int				= @compcode,
			@lprovidercode		Int				= @providercode,
			@lutildatefrom		Smalldatetime	= @utildatefrom,
			@lutildateto		Smalldatetime	= @utildateto,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lnodata			Bit				= 0

	EXEC sp_opensymmetric

	SELECT @rowcount = COUNT(1)
	FROM tblbatchape a  WITH(NOLOCK)
	WHERE ((@lnodata = 1 AND a.batchcode = 0 ) OR (@lnodata = 0 AND a.batchcode <> 0)) 
	AND a.statuscode = 2 AND a.compcode = @lcompcode AND  a.providercode = @lprovidercode
	OPTION(RECOMPILE)

	If @pageno <= 0 or @rowctr <= 0
		BEGIN
			SELECT a.batchcode, a.loano, a.compcode, a.providercode, 
			a.scheduledfrom, a.scheduledto, a.procedures, a.members, 
			a.dateencoded, a.statuscode, a.datecancelled, a.additionaltests,
			remarks = LTRIM(RTRIM(a.remarks)),
			ISNULL(b.contractno, '') AS contractno,
			ISNULL(dbo.decoder(b.ldflog, 0), '') AS companyname,
			ISNULL(LTRIM(RTRIM(b.initial)), '') AS companyinitial,
			ISNULL(c.providername, '') AS providername,
			ISNULL(d.username, '') AS encodedbyname,
			ISNULL(e.statusname, '') AS statusname
			FROM tblbatchape a WITH(NOLOCK)
			OUTER APPLY (SELECT compcode, contractno, ldflog, initial FROM tblcompany b WITH(NOLOCK) WHERE a.compcode = b.compcode) b
			OUTER APPLY (SELECT providercode, providername FROM tblproviders c WITH(NOLOCK) WHERE a.providercode = c.providercode) c
			OUTER APPLY (SELECT userno, username FROM tblusers d WITH(NOLOCK) WHERE a.encodedby = d.userno) d
			OUTER APPLY (SELECT statusno, statusname, statusfor FROM tblstatus e WITH(NOLOCK) WHERE a.statuscode = e.statusno AND e.statusfor = 'BATCHAPE') e
			WHERE ((@lnodata = 1 AND a.batchcode = 0 ) OR (@lnodata = 0 AND a.batchcode <> 0)) 
			AND a.statuscode = 2 AND a.compcode = @lcompcode AND  a.providercode = @lprovidercode
			AND (
				(
					YEAR(@lutildatefrom) = 1900 
					AND YEAR(@lutildateto) = 1900 
					AND a.batchcode <> 0
				)
				OR
				(
					YEAR(@lutildatefrom) <> 1900 
					AND YEAR(@lutildateto) <> 1900 
					AND (
						CAST(a.scheduledfrom AS DATE) >= CAST(@lutildatefrom AS DATE)
						AND CAST(a.scheduledto AS DATE) <= CAST(@lutildateto AS DATE)
					)
				)
			)
			ORDER BY loano
		END
	ELSE
		BEGIN
			SELECT a.batchcode, a.loano, a.compcode, a.providercode, 
			a.scheduledfrom, a.scheduledto, a.procedures, a.members, 
			a.dateencoded, a.statuscode, a.datecancelled, a.additionaltests,
			remarks = LTRIM(RTRIM(a.remarks)),
			ISNULL(b.contractno, '') AS contractno,
			ISNULL(dbo.decoder(b.ldflog, 0), '') AS companyname,
			ISNULL(LTRIM(RTRIM(b.initial)), '') AS companyinitial,
			ISNULL(c.providername, '') AS providername,
			ISNULL(d.username, '') AS encodedbyname,
			ISNULL(e.statusname, '') AS statusname
			FROM tblbatchape a WITH(NOLOCK)
			OUTER APPLY (SELECT compcode, contractno, ldflog, initial FROM tblcompany b WITH(NOLOCK) WHERE a.compcode = b.compcode) b
			OUTER APPLY (SELECT providercode, providername FROM tblproviders c WITH(NOLOCK) WHERE a.providercode = c.providercode) c
			OUTER APPLY (SELECT userno, username FROM tblusers d WITH(NOLOCK) WHERE a.encodedby = d.userno) d
			OUTER APPLY (SELECT statusno, statusname, statusfor FROM tblstatus e WITH(NOLOCK) WHERE a.statuscode = e.statusno AND e.statusfor = 'BATCHAPE') e
			WHERE ((@lnodata = 1 AND a.batchcode = 0 ) OR (@lnodata = 0 AND a.batchcode <> 0)) 
			AND a.statuscode = 2 AND a.compcode = @lcompcode AND  a.providercode = @lprovidercode
			AND (
				(
					YEAR(@lutildatefrom) = 1900 
					AND YEAR(@lutildateto) = 1900 
					AND a.batchcode <> 0
				)
				OR
				(
					YEAR(@lutildatefrom) <> 1900 
					AND YEAR(@lutildateto) <> 1900 
					AND (
						CAST(a.scheduledfrom AS DATE) >= CAST(@lutildatefrom AS DATE)
						AND CAST(a.scheduledto AS DATE) <= CAST(@lutildateto AS DATE)
					)
				)
			)
			ORDER BY loano
			OFFSET ((@lpageno - 1) * @lrowctr) ROWS
			FETCH NEXT @lrowctr ROWS ONLY
			OPTION(RECOMPILE)		
		END

	EXEC sp_closesymmetric
END

GO

-- ---- sp_getbatchapejournal ----
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getbatchapejournal] --''
	-- Add the parameters for the stored procedure here
	@batchcode	Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lbatchcode		Int		= @batchcode
	
    -- Insert statements for procedure here
	SELECT a.detno,
	description = LTRIM(RTRIM(a.description)),
	a.dateencoded, a.encodedby,
	encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), '')
	FROM tblbatchapejournal a WITH(NOLOCK)
	OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
	WHERE a.batchcode = @lbatchcode
	ORDER BY a.dateencoded
	OPTION(RECOMPILE)
END
GO

-- ---- sp_getbatchclaimloamembersv2 ----
CREATE   PROCEDURE [dbo].[sp_getbatchclaimloamembersv2] --1,11809, 93, 3, 2565, '12/19/2025', '12/21/2025', '', '', 11707
	-- Add the parameters for the stored procedure here
	
	@withplanICD	Bit,
	@compcode		Int,
	@providercode	Int,
	@billtype		Int,
	@subbilltype	Int,
	@utildatefrom	Smalldatetime,
	@utildateto		Smalldatetime,
	@membersearch	Varchar(240),
	@approvalcode	Varchar(20),
	@batchcode		Int,
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lwithplanICD	Bit				= @withplanICD,
			@lcompcode		Int				= @compcode,
			@lprovidercode	Int				= @providercode,
			@lbilltype		Int				= @billtype,
			@lsubbilltype	Int				= @subbilltype,
			@lutildatefrom	Smalldatetime	= @utildatefrom,
			@lutildateto	Smalldatetime	= @utildateto,
			@lmembersearch	Varchar(240)	= @membersearch,
			@lapprovalcode	Varchar(20)		= @approvalcode,
			@lbatchcode		Int				= @batchcode, --11692,
			@lpageno		Int				= @pageno,
			@lrowctr		Int				= @rowctr,
			@licdno			Int				= 0,
			@licddisease	Varchar(100)	= ''
			
    EXEC sp_opensymmetric
	EXEC sp_opensymmetriccompany

	IF(@lbatchcode = 0)
		BEGIN
			SELECT @rowcount = COUNT(1)
			FROM tblloas a WITH(NOLOCK)
			LEFT OUTER JOIN tblicdtable b WITH(NOLOCK) ON a.icdno = b.icdno
			LEFT OUTER JOIN tblmembernames c WITH(NOLOCK) ON c.membercode = a.membercode
			LEFT OUTER JOIN tblcompany d WITH(NOLOCK) ON d.compcode = @lcompcode
			WHERE a.loano <> '' AND a.loastatus IN (2,4,6)
			AND ((@lwithplanICD = 0 AND a.icdno = 0) OR (@lwithplanICD <> 0 AND a.plancode <> 0 AND a.icdno <> 0))
			AND ((@lcompcode = 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode))
			AND ((@lprovidercode = 0 AND a.loacode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
			AND ((@lbilltype = 0 AND a.loacode <> 0) OR (@lbilltype <> 0 AND a.claimtype = @lbilltype))
			AND ((@lsubbilltype = 0 AND a.loacode <> 0) OR (@lsubbilltype <> 0 AND a.subclaimtype = @lsubbilltype))
			AND ((YEAR(@lutildatefrom) = 1900 AND YEAR(@lutildateto) = 1900 AND a.loacode <> 0) OR
					(YEAR(@lutildatefrom) <> 1900 AND YEAR(@lutildateto) <> 1900 AND (
						CAST(a.dateavailed AS DATE) >= CAST(@lutildatefrom AS DATE) AND CAST(a.dateavailed AS DATE) <= CAST(@lutildateto AS DATE))
						))
			AND ((@lmembersearch = '' AND a.loacode <> 0) OR (@lmembersearch <> '' AND (a.memberno LIKE '%'+@lmembersearch+'%' OR dbo.Decrypt(a.membername) LIKE '%'+@lmembersearch+'%')))
			AND ((@lapprovalcode = '' AND a.loacode <> 0) OR (@lapprovalcode <> '' AND a.loano LIKE '%'+@lapprovalcode+'%'))
			OPTION(RECOMPILE)
		END
	ELSE
		BEGIN
			SELECT @rowcount = COUNT(1)
			FROM tblbatchapedetails a WITH(NOLOCK)
			OUTER APPLY (SELECT planname FROM tblcompanybenefitplan b WITH(NOLOCK) WHERE b.plancode = a.plancode) b
			OUTER APPLY (SELECT memberno FROM tblmembers c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
			OUTER APPLY (SELECT loano, compcode, scheduledfrom, scheduledto FROM tblbatchape d WITH(NOLOCK) WHERE d.batchcode = a.batchcode) d
			OUTER APPLY (SELECT effectivity, expiry FROM tblcompany e WITH(NOLOCK) WHERE e.compcode = d.compcode) e
			OUTER APPLY (SELECT membername FROM  tblmembernames f WITH(NOLOCK) WHERE f.membercode = a.membercode) f
			OUTER APPLY (SELECT enhancedencryption FROM tblcompany g WITH(NOLOCK) WHERE g.compcode = @lcompcode) g
			WHERE a.batchcode = @lbatchcode
			OPTION(RECOMPILE)
		END

	IF(@lbatchcode = 0)
		BEGIN
			IF @pageno <= 0 or @rowctr <= 0
				SELECT * FROM 
				(
					SELECT a.loacode, LTRIM(RTRIM(a.loano)) AS loano, 
						a.membercode, LTRIM(RTRIM(a.memberno)) AS memberno,
						membername = CASE WHEN d.enhancedencryption=1 THEN ISNULL(dbo.DecryptCompany(c.membername), '') ELSE dbo.Decrypt(a.membername) END,
						a.icdno,
						icddisease = LTRIM(RTRIM(ISNULL(b.icdcode,''))) + ' - ' + LTRIM(RTRIM(ISNULL(b.icddisease,''))),
						a.admittingtext,
						a.plancode, a.planname, a.loadate, a.dateavailed, a.datedue, a.coveredfrom, a.coveredto, a.loaamount
					FROM tblloas a WITH(NOLOCK)
					LEFT OUTER JOIN tblicdtable b WITH(NOLOCK) ON a.icdno = b.icdno
					LEFT OUTER JOIN tblmembernames c WITH(NOLOCK) ON c.membercode = a.membercode
					LEFT OUTER JOIN tblcompany d WITH(NOLOCK) ON d.compcode = @lcompcode

					--OUTER APPLY (SELECT icdcode, icddisease FROM tblicdtable b WITH(NOLOCK) WHERE a.icdno = b.icdno) b
					--OUTER APPLY (SELECT membername FROM  tblmembernames c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
					--OUTER APPLY (SELECT enhancedencryption FROM tblcompany d WITH(NOLOCK) WHERE d.compcode = @lcompcode) d
					WHERE a.loano <> '' AND a.loastatus IN (2,4,6)
					AND 
							((@lwithplanICD = 0 AND a.icdno = 0) OR (@lwithplanICD <> 0 AND a.plancode <> 0 AND a.icdno <> 0))
						AND ((@lcompcode = 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode))
						AND ((@lprovidercode = 0 AND a.loacode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
						AND ((@lbilltype = 0 AND a.loacode <> 0) OR (@lbilltype <> 0 AND a.claimtype = @lbilltype))
						AND ((@lsubbilltype = 0 AND a.loacode <> 0) OR (@lsubbilltype <> 0 AND a.subclaimtype = @lsubbilltype))
						AND ((YEAR(@lutildatefrom) = 1900 AND YEAR(@lutildateto) = 1900 AND a.loacode <> 0) OR
								(YEAR(@lutildatefrom) <> 1900 AND YEAR(@lutildateto) <> 1900 AND (
									CAST(a.dateavailed AS DATE) >= CAST(@lutildatefrom AS DATE) AND CAST(a.dateavailed AS DATE) <= CAST(@lutildateto AS DATE))
									))
						AND ((@lmembersearch = '' AND a.loacode <> 0) OR (@lmembersearch <> '' AND (a.memberno LIKE '%'+@lmembersearch+'%' OR dbo.Decrypt(a.membername) LIKE '%'+@lmembersearch+'%')))
						AND ((@lapprovalcode = '' AND a.loacode <> 0) OR (@lapprovalcode <> '' AND a.loano LIKE '%'+@lapprovalcode+'%'))
				) result
				ORDER BY membername 
			ELSE
				SELECT * FROM 
				(
					SELECT a.loacode, LTRIM(RTRIM(a.loano)) AS loano, 
						a.membercode, LTRIM(RTRIM(a.memberno)) AS memberno,
						membername = CASE WHEN d.enhancedencryption=1 THEN ISNULL(dbo.DecryptCompany(c.membername), '') ELSE dbo.Decrypt(a.membername) END,
						a.icdno,
						icddisease = LTRIM(RTRIM(ISNULL(b.icdcode,''))) + ' - ' + LTRIM(RTRIM(ISNULL(b.icddisease,''))),
						a.admittingtext,
						a.plancode, a.planname, a.loadate, a.dateavailed, a.datedue, a.coveredfrom, a.coveredto, a.loaamount
					FROM tblloas a WITH(NOLOCK)
					LEFT OUTER JOIN tblicdtable b WITH(NOLOCK) ON a.icdno = b.icdno
					LEFT OUTER JOIN tblmembernames c WITH(NOLOCK) ON c.membercode = a.membercode
					LEFT OUTER JOIN tblcompany d WITH(NOLOCK) ON d.compcode = @lcompcode

					--OUTER APPLY (SELECT icdcode, icddisease FROM tblicdtable b WITH(NOLOCK) WHERE a.icdno = b.icdno) b
					--OUTER APPLY (SELECT membername FROM  tblmembernames c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
					--OUTER APPLY (SELECT enhancedencryption FROM tblcompany d WITH(NOLOCK) WHERE d.compcode = @lcompcode) d
					WHERE a.loano <> '' AND a.loastatus IN (2,4,6)
					AND 
							((@lwithplanICD = 0 AND a.icdno = 0) OR (@lwithplanICD <> 0 AND a.plancode <> 0 AND a.icdno <> 0))
						AND ((@lcompcode = 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode))
						AND ((@lprovidercode = 0 AND a.loacode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
						AND ((@lbilltype = 0 AND a.loacode <> 0) OR (@lbilltype <> 0 AND a.claimtype = @lbilltype))
						AND ((@lsubbilltype = 0 AND a.loacode <> 0) OR (@lsubbilltype <> 0 AND a.subclaimtype = @lsubbilltype))
						AND ((YEAR(@lutildatefrom) = 1900 AND YEAR(@lutildateto) = 1900 AND a.loacode <> 0) OR
								(YEAR(@lutildatefrom) <> 1900 AND YEAR(@lutildateto) <> 1900 AND (
									CAST(a.dateavailed AS DATE) >= CAST(@lutildatefrom AS DATE) AND CAST(a.dateavailed AS DATE) <= CAST(@lutildateto AS DATE))
									))
						AND ((@lmembersearch = '' AND a.loacode <> 0) OR (@lmembersearch <> '' AND (a.memberno LIKE '%'+@lmembersearch+'%' OR dbo.Decrypt(a.membername) LIKE '%'+@lmembersearch+'%')))
						AND ((@lapprovalcode = '' AND a.loacode <> 0) OR (@lapprovalcode <> '' AND a.loano LIKE '%'+@lapprovalcode+'%'))
				) result
				ORDER BY membername
				OFFSET ((@lpageno - 1) * @lrowctr) ROWS
				FETCH NEXT @lrowctr ROWS ONLY
				OPTION(RECOMPILE)
		END
	ELSE	
		BEGIN
			SELECT 
				@licdno = ISNULL(b.icdno, 0),
				@licddisease = ISNULL(b.icddisease, '')
			FROM tblsettingsmedical a
			OUTER APPLY (SELECT icdcode, icddisease, icdno FROM tblicdtable b WITH(NOLOCK) WHERE a.apeicdcode = b.icdcode) b

			IF @pageno <= 0 or @rowctr <= 0
				SELECT * FROM 
				(
					SELECT
						loacode = 0, 
						loano = d.loano, 
						membercode = a.membercode,
						memberno = ISNULL(c.memberno, ''),
						membername = CASE WHEN g.enhancedencryption=1 THEN ISNULL(dbo.DecryptCompany(f.membername), '') ELSE dbo.Decrypt(a.membername) END,
						icdno = @licdno,
						icddisease = @licddisease,
						admittingtext = '',
						plancode = a.plancode,
						planname = ISNULL(b.planname, ''), 
						loadate = d.scheduledfrom, 
						dateavailed = d.scheduledfrom, 
						datedue = d.scheduledto, 
						coveredfrom = e.effectivity, 
						coveredto = e.expiry, 
						loaamount = 0.00 
					FROM tblbatchapedetails a WITH(NOLOCK)
					OUTER APPLY (SELECT planname FROM tblcompanybenefitplan b WITH(NOLOCK) WHERE b.plancode = a.plancode) b
					OUTER APPLY (SELECT memberno FROM tblmembers c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
					OUTER APPLY (SELECT loano, compcode, scheduledfrom, scheduledto FROM tblbatchape d WITH(NOLOCK) WHERE d.batchcode = a.batchcode) d
					OUTER APPLY (SELECT effectivity, expiry FROM tblcompany e WITH(NOLOCK) WHERE e.compcode = d.compcode) e
					OUTER APPLY (SELECT membername FROM  tblmembernames f WITH(NOLOCK) WHERE f.membercode = a.membercode) f
					OUTER APPLY (SELECT enhancedencryption FROM tblcompany g WITH(NOLOCK) WHERE g.compcode = @lcompcode) g
					WHERE a.batchcode = @lbatchcode
				) result
				ORDER BY membername
			ELSE
				SELECT * FROM 
				(
					SELECT
						loacode = 0, 
						loano = d.loano, 
						membercode = a.membercode,
						memberno = ISNULL(c.memberno, ''),
						membername = CASE WHEN g.enhancedencryption=1 THEN ISNULL(dbo.DecryptCompany(f.membername), '') ELSE dbo.Decrypt(a.membername) END,
						icdno = @licdno,
						icddisease = @licddisease,
						admittingtext = '',
						plancode = a.plancode,
						planname = ISNULL(b.planname, ''), 
						loadate = d.scheduledfrom, 
						dateavailed = d.scheduledfrom, 
						datedue = d.scheduledto, 
						coveredfrom = e.effectivity, 
						coveredto = e.expiry, 
						loaamount = 0.00 
					FROM tblbatchapedetails a WITH(NOLOCK)
					OUTER APPLY (SELECT planname FROM tblcompanybenefitplan b WITH(NOLOCK) WHERE b.plancode = a.plancode) b
					OUTER APPLY (SELECT memberno FROM tblmembers c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
					OUTER APPLY (SELECT loano, compcode, scheduledfrom, scheduledto FROM tblbatchape d WITH(NOLOCK) WHERE d.batchcode = a.batchcode) d
					OUTER APPLY (SELECT effectivity, expiry FROM tblcompany e WITH(NOLOCK) WHERE e.compcode = d.compcode) e
					OUTER APPLY (SELECT membername FROM  tblmembernames f WITH(NOLOCK) WHERE f.membercode = a.membercode) f
					OUTER APPLY (SELECT enhancedencryption FROM tblcompany g WITH(NOLOCK) WHERE g.compcode = @lcompcode) g
					WHERE a.batchcode = @lbatchcode
				) result
				ORDER BY membername
				OFFSET ((@lpageno - 1) * @lrowctr) ROWS
				FETCH NEXT @lrowctr ROWS ONLY
				OPTION(RECOMPILE)
		END

	EXEC sp_closesymmetriccompany
	EXEC sp_closesymmetric
		
END
GO

-- ---- sp_getbatchclaimloamembersv3 ----
CREATE   PROCEDURE [dbo].[sp_getbatchclaimloamembersv3] --1,11809, 93, 3, 2565, '12/19/2025', '12/21/2025', '', '', 11707
	-- Add the parameters for the stored procedure here
	
	@withplanICD	Bit,
	@compcode		Int,
	@providercode	Int,
	@billtype		Int,
	@subbilltype	Int,
	@utildatefrom	Smalldatetime,
	@utildateto		Smalldatetime,
	@membersearch	Varchar(240),
	@approvalcode	Varchar(20),
	@batchcode		VARCHAR(MAX),
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lwithplanICD	Bit				= @withplanICD,
			@lcompcode		Int				= @compcode,
			@lprovidercode	Int				= @providercode,
			@lbilltype		Int				= @billtype,
			@lsubbilltype	Int				= @subbilltype,
			@lutildatefrom	Smalldatetime	= @utildatefrom,
			@lutildateto	Smalldatetime	= @utildateto,
			@lmembersearch	Varchar(240)	= @membersearch,
			@lapprovalcode	Varchar(20)		= @approvalcode,
			@lbatchcode		VARCHAR(MAX)	= @batchcode, --11692,
			@lpageno		Int				= @pageno,
			@lrowctr		Int				= @rowctr,
			@licdno			Int				= 0,
			@licddisease	Varchar(100)	= ''
			
    EXEC sp_opensymmetric
	EXEC sp_opensymmetriccompany

	IF(@lbatchcode = '')
		BEGIN
			SELECT @rowcount = COUNT(1)
			FROM tblloas a WITH(NOLOCK)
			LEFT OUTER JOIN tblicdtable b WITH(NOLOCK) ON a.icdno = b.icdno
			LEFT OUTER JOIN tblmembernames c WITH(NOLOCK) ON c.membercode = a.membercode
			LEFT OUTER JOIN tblcompany d WITH(NOLOCK) ON d.compcode = @lcompcode
			WHERE a.loano <> '' AND a.loastatus IN (2,4,6)
			AND ((@lwithplanICD = 0 AND a.icdno = 0) OR (@lwithplanICD <> 0 AND a.plancode <> 0 AND a.icdno <> 0))
			AND ((@lcompcode = 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode))
			AND ((@lprovidercode = 0 AND a.loacode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
			AND ((@lbilltype = 0 AND a.loacode <> 0) OR (@lbilltype <> 0 AND a.claimtype = @lbilltype))
			AND ((@lsubbilltype = 0 AND a.loacode <> 0) OR (@lsubbilltype <> 0 AND a.subclaimtype = @lsubbilltype))
			AND ((YEAR(@lutildatefrom) = 1900 AND YEAR(@lutildateto) = 1900 AND a.loacode <> 0) OR
					(YEAR(@lutildatefrom) <> 1900 AND YEAR(@lutildateto) <> 1900 AND (
						CAST(a.dateavailed AS DATE) >= CAST(@lutildatefrom AS DATE) AND CAST(a.dateavailed AS DATE) <= CAST(@lutildateto AS DATE))
						))
			AND ((@lmembersearch = '' AND a.loacode <> 0) OR (@lmembersearch <> '' AND (a.memberno LIKE '%'+@lmembersearch+'%' OR dbo.Decrypt(a.membername) LIKE '%'+@lmembersearch+'%')))
			AND ((@lapprovalcode = '' AND a.loacode <> 0) OR (@lapprovalcode <> '' AND a.loano LIKE '%'+@lapprovalcode+'%'))
			OPTION(RECOMPILE)
		END
	ELSE
		BEGIN
			SELECT @rowcount = COUNT(1)
			FROM tblbatchapedetails a WITH(NOLOCK)
			OUTER APPLY (SELECT planname FROM tblcompanybenefitplan b WITH(NOLOCK) WHERE b.plancode = a.plancode) b
			OUTER APPLY (SELECT memberno FROM tblmembers c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
			OUTER APPLY (SELECT loano, compcode, scheduledfrom, scheduledto FROM tblbatchape d WITH(NOLOCK) WHERE d.batchcode = a.batchcode) d
			OUTER APPLY (SELECT effectivity, expiry FROM tblcompany e WITH(NOLOCK) WHERE e.compcode = d.compcode) e
			OUTER APPLY (SELECT membername FROM  tblmembernames f WITH(NOLOCK) WHERE f.membercode = a.membercode) f
			OUTER APPLY (SELECT enhancedencryption FROM tblcompany g WITH(NOLOCK) WHERE g.compcode = @lcompcode) g
			WHERE (
				(@lbatchcode IS NULL OR @lbatchcode = '')
				OR a.batchcode IN (
					SELECT TRY_CAST(T.c.value('.', 'INT') AS INT)
					FROM (
						SELECT CAST('<x>' + REPLACE(@lbatchcode, '_', '</x><x>') + '</x>' AS XML) AS xmlData
					) AS A
					CROSS APPLY xmlData.nodes('/x') AS T(c)
					WHERE TRY_CAST(T.c.value('.', 'INT') AS INT) IS NOT NULL
				)
			)
			OPTION(RECOMPILE)
		END

	IF(@lbatchcode = '')
		BEGIN
			IF @pageno <= 0 or @rowctr <= 0
				SELECT * FROM 
				(
					SELECT a.loacode, LTRIM(RTRIM(a.loano)) AS loano, 
						a.membercode, LTRIM(RTRIM(a.memberno)) AS memberno,
						membername = CASE WHEN d.enhancedencryption=1 THEN ISNULL(dbo.DecryptCompany(c.membername), '') ELSE dbo.Decrypt(a.membername) END,
						a.icdno,
						icddisease = LTRIM(RTRIM(ISNULL(b.icdcode,''))) + ' - ' + LTRIM(RTRIM(ISNULL(b.icddisease,''))),
						a.admittingtext,
						a.plancode, a.planname, a.loadate, a.dateavailed, a.datedue, a.coveredfrom, a.coveredto, a.loaamount
					FROM tblloas a WITH(NOLOCK)
					LEFT OUTER JOIN tblicdtable b WITH(NOLOCK) ON a.icdno = b.icdno
					LEFT OUTER JOIN tblmembernames c WITH(NOLOCK) ON c.membercode = a.membercode
					LEFT OUTER JOIN tblcompany d WITH(NOLOCK) ON d.compcode = @lcompcode

					--OUTER APPLY (SELECT icdcode, icddisease FROM tblicdtable b WITH(NOLOCK) WHERE a.icdno = b.icdno) b
					--OUTER APPLY (SELECT membername FROM  tblmembernames c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
					--OUTER APPLY (SELECT enhancedencryption FROM tblcompany d WITH(NOLOCK) WHERE d.compcode = @lcompcode) d
					WHERE a.loano <> '' AND a.loastatus IN (2,4,6)
					AND 
							((@lwithplanICD = 0 AND a.icdno = 0) OR (@lwithplanICD <> 0 AND a.plancode <> 0 AND a.icdno <> 0))
						AND ((@lcompcode = 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode))
						AND ((@lprovidercode = 0 AND a.loacode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
						AND ((@lbilltype = 0 AND a.loacode <> 0) OR (@lbilltype <> 0 AND a.claimtype = @lbilltype))
						AND ((@lsubbilltype = 0 AND a.loacode <> 0) OR (@lsubbilltype <> 0 AND a.subclaimtype = @lsubbilltype))
						AND ((YEAR(@lutildatefrom) = 1900 AND YEAR(@lutildateto) = 1900 AND a.loacode <> 0) OR
								(YEAR(@lutildatefrom) <> 1900 AND YEAR(@lutildateto) <> 1900 AND (
									CAST(a.dateavailed AS DATE) >= CAST(@lutildatefrom AS DATE) AND CAST(a.dateavailed AS DATE) <= CAST(@lutildateto AS DATE))
									))
						AND ((@lmembersearch = '' AND a.loacode <> 0) OR (@lmembersearch <> '' AND (a.memberno LIKE '%'+@lmembersearch+'%' OR dbo.Decrypt(a.membername) LIKE '%'+@lmembersearch+'%')))
						AND ((@lapprovalcode = '' AND a.loacode <> 0) OR (@lapprovalcode <> '' AND a.loano LIKE '%'+@lapprovalcode+'%'))
				) result
				ORDER BY membername 
			ELSE
				SELECT * FROM 
				(
					SELECT a.loacode, LTRIM(RTRIM(a.loano)) AS loano, 
						a.membercode, LTRIM(RTRIM(a.memberno)) AS memberno,
						membername = CASE WHEN d.enhancedencryption=1 THEN ISNULL(dbo.DecryptCompany(c.membername), '') ELSE dbo.Decrypt(a.membername) END,
						a.icdno,
						icddisease = LTRIM(RTRIM(ISNULL(b.icdcode,''))) + ' - ' + LTRIM(RTRIM(ISNULL(b.icddisease,''))),
						a.admittingtext,
						a.plancode, a.planname, a.loadate, a.dateavailed, a.datedue, a.coveredfrom, a.coveredto, a.loaamount
					FROM tblloas a WITH(NOLOCK)
					LEFT OUTER JOIN tblicdtable b WITH(NOLOCK) ON a.icdno = b.icdno
					LEFT OUTER JOIN tblmembernames c WITH(NOLOCK) ON c.membercode = a.membercode
					LEFT OUTER JOIN tblcompany d WITH(NOLOCK) ON d.compcode = @lcompcode

					--OUTER APPLY (SELECT icdcode, icddisease FROM tblicdtable b WITH(NOLOCK) WHERE a.icdno = b.icdno) b
					--OUTER APPLY (SELECT membername FROM  tblmembernames c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
					--OUTER APPLY (SELECT enhancedencryption FROM tblcompany d WITH(NOLOCK) WHERE d.compcode = @lcompcode) d
					WHERE a.loano <> '' AND a.loastatus IN (2,4,6)
					AND 
							((@lwithplanICD = 0 AND a.icdno = 0) OR (@lwithplanICD <> 0 AND a.plancode <> 0 AND a.icdno <> 0))
						AND ((@lcompcode = 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode))
						AND ((@lprovidercode = 0 AND a.loacode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
						AND ((@lbilltype = 0 AND a.loacode <> 0) OR (@lbilltype <> 0 AND a.claimtype = @lbilltype))
						AND ((@lsubbilltype = 0 AND a.loacode <> 0) OR (@lsubbilltype <> 0 AND a.subclaimtype = @lsubbilltype))
						AND ((YEAR(@lutildatefrom) = 1900 AND YEAR(@lutildateto) = 1900 AND a.loacode <> 0) OR
								(YEAR(@lutildatefrom) <> 1900 AND YEAR(@lutildateto) <> 1900 AND (
									CAST(a.dateavailed AS DATE) >= CAST(@lutildatefrom AS DATE) AND CAST(a.dateavailed AS DATE) <= CAST(@lutildateto AS DATE))
									))
						AND ((@lmembersearch = '' AND a.loacode <> 0) OR (@lmembersearch <> '' AND (a.memberno LIKE '%'+@lmembersearch+'%' OR dbo.Decrypt(a.membername) LIKE '%'+@lmembersearch+'%')))
						AND ((@lapprovalcode = '' AND a.loacode <> 0) OR (@lapprovalcode <> '' AND a.loano LIKE '%'+@lapprovalcode+'%'))
				) result
				ORDER BY membername
				OFFSET ((@lpageno - 1) * @lrowctr) ROWS
				FETCH NEXT @lrowctr ROWS ONLY
				OPTION(RECOMPILE)
		END
	ELSE	
		BEGIN
			SELECT 
				@licdno = ISNULL(b.icdno, 0),
				@licddisease = ISNULL(b.icddisease, '')
			FROM tblsettingsmedical a
			OUTER APPLY (SELECT icdcode, icddisease, icdno FROM tblicdtable b WITH(NOLOCK) WHERE a.apeicdcode = b.icdcode) b

			IF @pageno <= 0 or @rowctr <= 0
				SELECT * FROM 
				(
					SELECT
						loacode = 0, 
						loano = d.loano, 
						membercode = a.membercode,
						memberno = ISNULL(c.memberno, ''),
						membername = CASE WHEN g.enhancedencryption=1 THEN ISNULL(dbo.DecryptCompany(f.membername), '') ELSE dbo.Decrypt(a.membername) END,
						icdno = @licdno,
						icddisease = @licddisease,
						admittingtext = '',
						plancode = a.plancode,
						planname = ISNULL(b.planname, ''), 
						loadate = d.scheduledfrom, 
						dateavailed = d.scheduledfrom, 
						datedue = d.scheduledto, 
						coveredfrom = e.effectivity, 
						coveredto = e.expiry, 
						loaamount = 0.00 
					FROM tblbatchapedetails a WITH(NOLOCK)
					OUTER APPLY (SELECT planname FROM tblcompanybenefitplan b WITH(NOLOCK) WHERE b.plancode = a.plancode) b
					OUTER APPLY (SELECT memberno FROM tblmembers c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
					OUTER APPLY (SELECT loano, compcode, scheduledfrom, scheduledto FROM tblbatchape d WITH(NOLOCK) WHERE d.batchcode = a.batchcode) d
					OUTER APPLY (SELECT effectivity, expiry FROM tblcompany e WITH(NOLOCK) WHERE e.compcode = d.compcode) e
					OUTER APPLY (SELECT membername FROM  tblmembernames f WITH(NOLOCK) WHERE f.membercode = a.membercode) f
					OUTER APPLY (SELECT enhancedencryption FROM tblcompany g WITH(NOLOCK) WHERE g.compcode = @lcompcode) g
					WHERE (
						(@lbatchcode IS NULL OR @lbatchcode = '')
						OR a.batchcode IN (
							SELECT TRY_CAST(T.c.value('.', 'INT') AS INT)
							FROM (
								SELECT CAST('<x>' + REPLACE(@lbatchcode, '_', '</x><x>') + '</x>' AS XML) AS xmlData
							) AS A
							CROSS APPLY xmlData.nodes('/x') AS T(c)
							WHERE TRY_CAST(T.c.value('.', 'INT') AS INT) IS NOT NULL
						)
					)
				) result
				ORDER BY membername
			ELSE
				SELECT * FROM 
				(
					SELECT
						loacode = 0, 
						loano = d.loano, 
						membercode = a.membercode,
						memberno = ISNULL(c.memberno, ''),
						membername = CASE WHEN g.enhancedencryption=1 THEN ISNULL(dbo.DecryptCompany(f.membername), '') ELSE dbo.Decrypt(a.membername) END,
						icdno = @licdno,
						icddisease = @licddisease,
						admittingtext = '',
						plancode = a.plancode,
						planname = ISNULL(b.planname, ''), 
						loadate = d.scheduledfrom, 
						dateavailed = d.scheduledfrom, 
						datedue = d.scheduledto, 
						coveredfrom = e.effectivity, 
						coveredto = e.expiry, 
						loaamount = 0.00 
					FROM tblbatchapedetails a WITH(NOLOCK)
					OUTER APPLY (SELECT planname FROM tblcompanybenefitplan b WITH(NOLOCK) WHERE b.plancode = a.plancode) b
					OUTER APPLY (SELECT memberno FROM tblmembers c WITH(NOLOCK) WHERE c.membercode = a.membercode) c
					OUTER APPLY (SELECT loano, compcode, scheduledfrom, scheduledto FROM tblbatchape d WITH(NOLOCK) WHERE d.batchcode = a.batchcode) d
					OUTER APPLY (SELECT effectivity, expiry FROM tblcompany e WITH(NOLOCK) WHERE e.compcode = d.compcode) e
					OUTER APPLY (SELECT membername FROM  tblmembernames f WITH(NOLOCK) WHERE f.membercode = a.membercode) f
					OUTER APPLY (SELECT enhancedencryption FROM tblcompany g WITH(NOLOCK) WHERE g.compcode = @lcompcode) g
					WHERE (
						(@lbatchcode IS NULL OR @lbatchcode = '')
						OR a.batchcode IN (
							SELECT TRY_CAST(T.c.value('.', 'INT') AS INT)
							FROM (
								SELECT CAST('<x>' + REPLACE(@lbatchcode, '_', '</x><x>') + '</x>' AS XML) AS xmlData
							) AS A
							CROSS APPLY xmlData.nodes('/x') AS T(c)
							WHERE TRY_CAST(T.c.value('.', 'INT') AS INT) IS NOT NULL
						)
					)
				) result
				ORDER BY membername
				OFFSET ((@lpageno - 1) * @lrowctr) ROWS
				FETCH NEXT @lrowctr ROWS ONLY
				OPTION(RECOMPILE)
		END

	EXEC sp_closesymmetriccompany
	EXEC sp_closesymmetric
		
END

--SELECT *
--FROM (VALUES
--(
--    CAST(0 AS INT),          -- loacode
--    CAST('' AS VARCHAR(50)), -- loano
--    CAST(0 AS INT),          -- membercode
--    CAST('' AS VARCHAR(50)), -- memberno
--    CAST('' AS VARCHAR(150)),-- membername
--    CAST(0 AS INT),          -- icdno
--    CAST('' AS VARCHAR(255)),-- icddisease
--    CAST('' AS VARCHAR(255)),-- admittingtext
--    CAST(0 AS INT),          -- plancode
--    CAST('' AS VARCHAR(150)),-- planname
--    CAST(GETDATE() AS DATETIME), -- loadate
--    CAST(GETDATE() AS DATETIME), -- dateavailed
--    CAST(GETDATE() AS DATETIME), -- datedue
--    CAST(GETDATE() AS DATETIME), -- coveredfrom
--    CAST(GETDATE() AS DATETIME), -- coveredto
--    CAST(0 AS DECIMAL(18,2)) -- loaamount
--),
--(
--    CAST(0 AS INT),
--    CAST('' AS VARCHAR(50)),
--    CAST(0 AS INT),
--    CAST('' AS VARCHAR(50)),
--    CAST('' AS VARCHAR(150)),
--    CAST(0 AS INT),
--    CAST('' AS VARCHAR(255)),
--    CAST('' AS VARCHAR(255)),
--    CAST(0 AS INT),
--    CAST('' AS VARCHAR(150)),
--    CAST(GETDATE() AS DATETIME),
--    CAST(GETDATE() AS DATETIME),
--    CAST(GETDATE() AS DATETIME),
--    CAST(GETDATE() AS DATETIME),
--    CAST(GETDATE() AS DATETIME),
--    CAST(0 AS DECIMAL(18,2))
--)
--) AS t(
--    loacode,
--    loano,
--    membercode,
--    memberno,
--    membername,
--    icdno,
--    icddisease,
--    admittingtext,
--    plancode,
--    planname,
--    loadate,
--    dateavailed,
--    datedue,
--    coveredfrom,
--    coveredto,
--    loaamount
--);
GO

-- ---- sp_getbatchclaimsuploadforpfv3 ----
CREATE PROCEDURE [dbo].[sp_getbatchclaimsuploadforpfv3] --1,20
	-- Add the parameters for the stored procedure here
	
	@importedfrom	Smalldatetime,
	@importedto		Smalldatetime,
	@batchno		Varchar(20),
	@status			Int,
	@importedby		Varchar(150),
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@limportedfrom	Smalldatetime		= @importedfrom,
			@limportedto	Smalldatetime		= @importedto,
			@lbatchno		Varchar(20)			= @batchno,
			@lstatus		Int					= @status,
			@limportedby	Varchar(150)		= @importedby,
			@lpageno		Int					= @pageno,
			@lrowctr		Int					= @rowctr
	
	EXEC sp_opensymmetric

	SELECT @rowcount = COUNT(1)
	FROM tbluploadbatchclaims a WITH(NOLOCK)
	OUTER APPLY (SELECT statusname FROM tblstatus b WITH(NOLOCK) WHERE b.statusfor = 'UPLOAD BATCH CLAIMS' AND b.statusno = a.statuscode) b
	OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE c.userno = a.uploadedby) c
	WHERE a.uploadtype = 1 
	AND ((YEAR(@limportedfrom) = 1900 AND YEAR(@limportedto) = 1900 AND a.batchcode <> 0) OR
			(YEAR(@limportedfrom) <> 1900 AND YEAR(@limportedto) <> 1900 AND (
				CAST(a.dateuploaded AS DATE) >= CAST(@limportedfrom AS DATE) AND CAST(a.dateuploaded AS DATE) <= CAST(@limportedto AS DATE))
				))
	AND ((@lstatus = 0 AND a.batchcode <> 0) OR (@lstatus <> 0 AND a.statuscode = @lstatus))
	AND ((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%' + @lbatchno + '%'))
	AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
	OPTION(RECOMPILE)

    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		(
			SELECT 
				a.batchcode, 
				a.batchno, 
				a.uploadcount,
				a.statuscode,
				statusname = ISNULL(RTRIM(LTRIM(b.statusname)),''),
				a.datestarted, a.datefinished, a.datecancelled,
				importedby = ISNULL(RTRIM(LTRIM(c.username)),''), 
				dateimported = a.dateuploaded,
				a.remarks, a.duration,
				cancelledby = ISNULL(RTRIM(LTRIM(d.username)), '')
			FROM tbluploadbatchclaims a WITH(NOLOCK)
			OUTER APPLY (SELECT statusname FROM tblstatus b WITH(NOLOCK) WHERE b.statusfor = 'UPLOAD BATCH CLAIMS' AND b.statusno = a.statuscode) b
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE c.userno = a.uploadedby) c
			OUTER APPLY (SELECT username FROM tblusers d WITH(NOLOCK) WHERE d.userno = a.cancelledby) d
			WHERE a.uploadtype = 1
			AND ((YEAR(@limportedfrom) = 1900 AND YEAR(@limportedto) = 1900 AND a.batchcode <> 0) OR 
			(YEAR(@limportedfrom) <> 1900 AND YEAR(@limportedto) <> 1900 AND 
			(CAST(a.dateuploaded AS DATE) >= CAST(@limportedfrom AS DATE) AND CAST(a.dateuploaded AS DATE) <= CAST(@limportedto AS DATE))))
			AND ((@lstatus = 0 AND a.batchcode <> 0) OR (@lstatus <> 0 AND a.statuscode = @lstatus))
			AND ((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%' + @lbatchno + '%'))
			AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
		) result
		ORDER BY dateimported DESC
	ELSE
		SELECT * FROM
		(
			SELECT 
				a.batchcode, 
				a.batchno, 
				a.uploadcount,
				a.statuscode,
				statusname = ISNULL(RTRIM(LTRIM(b.statusname)),''),
				a.datestarted, a.datefinished, a.datecancelled,
				importedby = ISNULL(RTRIM(LTRIM(c.username)),''), 
				dateimported = a.dateuploaded,
				a.remarks, a.duration,
				cancelledby = ISNULL(RTRIM(LTRIM(d.username)), '')
			FROM tbluploadbatchclaims a WITH(NOLOCK)
			OUTER APPLY (SELECT statusname FROM tblstatus b WITH(NOLOCK) WHERE b.statusfor = 'UPLOAD BATCH CLAIMS' AND b.statusno = a.statuscode) b
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE c.userno = a.uploadedby) c
			OUTER APPLY (SELECT username FROM tblusers d WITH(NOLOCK) WHERE d.userno = a.cancelledby) d
			WHERE a.uploadtype = 1
			AND ((YEAR(@limportedfrom) = 1900 AND YEAR(@limportedto) = 1900 AND a.batchcode <> 0) OR 
			(YEAR(@limportedfrom) <> 1900 AND YEAR(@limportedto) <> 1900 AND 
			(CAST(a.dateuploaded AS DATE) >= CAST(@limportedfrom AS DATE) AND CAST(a.dateuploaded AS DATE) <= CAST(@limportedto AS DATE))))
			AND ((@lstatus = 0 AND a.batchcode <> 0) OR (@lstatus <> 0 AND a.statuscode = @lstatus))
			AND ((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%' + @lbatchno + '%'))
			AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
		) result
		ORDER BY dateimported DESC
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)

	EXEC sp_closesymmetric
END
GO

-- ---- sp_getbatchclaimsuploadfortelemedv2 ----
CREATE PROCEDURE [dbo].[sp_getbatchclaimsuploadfortelemedv2] --1,20
	-- Add the parameters for the stored procedure here
	
	@importedfrom	Smalldatetime,
	@importedto		Smalldatetime,
	@batchno		Varchar(20),
	@status			Int,
	@importedby		Varchar(150),
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@limportedfrom	Smalldatetime		= @importedfrom,
			@limportedto	Smalldatetime		= @importedto,
			@lbatchno		Varchar(20)			= @batchno,
			@lstatus		Int					= @status,
			@limportedby	Varchar(150)		= @importedby,
			@lpageno		Int					= @pageno,
			@lrowctr		Int					= @rowctr
	
	EXEC sp_opensymmetric

	SELECT @rowcount = COUNT(1)
	FROM tbluploadbatchclaims a WITH(NOLOCK)
	OUTER APPLY (SELECT statusname FROM tblstatus b WITH(NOLOCK) WHERE b.statusfor = 'UPLOAD BATCH CLAIMS' AND b.statusno = a.statuscode) b
	OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE c.userno = a.uploadedby) c
	WHERE a.uploadtype = 2 AND
	((YEAR(@limportedfrom) = 1900 AND YEAR(@limportedto) = 1900 AND a.batchcode <> 0) OR
			(YEAR(@limportedfrom) <> 1900 AND YEAR(@limportedto) <> 1900 AND (
				CAST(a.dateuploaded AS DATE) >= CAST(@limportedfrom AS DATE) AND CAST(a.dateuploaded AS DATE) <= CAST(@limportedto AS DATE))
				))
	AND ((@lstatus = 0 AND a.batchcode <> 0) OR (@lstatus <> 0 AND a.statuscode = @lstatus))
	AND ((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%' + @lbatchno + '%'))
	AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
	OPTION(RECOMPILE)

    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		(
			SELECT 
				a.batchcode, 
				a.batchno, 
				a.uploadcount,
				a.statuscode,
				statusname = ISNULL(RTRIM(LTRIM(b.statusname)),''),
				a.datestarted, a.datefinished, a.datecancelled,
				importedby = ISNULL(RTRIM(LTRIM(c.username)),''), 
				dateimported = a.dateuploaded,
				a.remarks, a.duration,
				cancelledby = ISNULL(RTRIM(LTRIM(d.username)), '')
			FROM tbluploadbatchclaims a WITH(NOLOCK)
			OUTER APPLY (SELECT statusname FROM tblstatus b WITH(NOLOCK) WHERE b.statusfor = 'UPLOAD BATCH CLAIMS' AND b.statusno = a.statuscode) b
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE c.userno = a.uploadedby) c
			OUTER APPLY (SELECT username FROM tblusers d WITH(NOLOCK) WHERE d.userno = a.cancelledby) d
			WHERE a.uploadtype = 2
			AND ((YEAR(@limportedfrom) = 1900 AND YEAR(@limportedto) = 1900 AND a.batchcode <> 0) OR 
			(YEAR(@limportedfrom) <> 1900 AND YEAR(@limportedto) <> 1900 AND 
			(CAST(a.dateuploaded AS DATE) >= CAST(@limportedfrom AS DATE) AND CAST(a.dateuploaded AS DATE) <= CAST(@limportedto AS DATE))))
			AND ((@lstatus = 0 AND a.batchcode <> 0) OR (@lstatus <> 0 AND a.statuscode = @lstatus))
			AND ((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%' + @lbatchno + '%'))
			AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
		) result
		ORDER BY dateimported DESC
	ELSE
		SELECT * FROM
		(
			SELECT 
				a.batchcode, 
				a.batchno, 
				a.uploadcount,
				a.statuscode,
				statusname = ISNULL(RTRIM(LTRIM(b.statusname)),''),
				a.datestarted, a.datefinished, a.datecancelled,
				importedby = ISNULL(RTRIM(LTRIM(c.username)),''), 
				dateimported = a.dateuploaded,
				a.remarks, a.duration,
				cancelledby = ISNULL(RTRIM(LTRIM(d.username)), '')
			FROM tbluploadbatchclaims a WITH(NOLOCK)
			OUTER APPLY (SELECT statusname FROM tblstatus b WITH(NOLOCK) WHERE b.statusfor = 'UPLOAD BATCH CLAIMS' AND b.statusno = a.statuscode) b
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE c.userno = a.uploadedby) c
			OUTER APPLY (SELECT username FROM tblusers d WITH(NOLOCK) WHERE d.userno = a.cancelledby) d
			WHERE a.uploadtype = 2
			AND ((YEAR(@limportedfrom) = 1900 AND YEAR(@limportedto) = 1900 AND a.batchcode <> 0) OR 
			(YEAR(@limportedfrom) <> 1900 AND YEAR(@limportedto) <> 1900 AND 
			(CAST(a.dateuploaded AS DATE) >= CAST(@limportedfrom AS DATE) AND CAST(a.dateuploaded AS DATE) <= CAST(@limportedto AS DATE))))
			AND ((@lstatus = 0 AND a.batchcode <> 0) OR (@lstatus <> 0 AND a.statuscode = @lstatus))
			AND ((@lbatchno = '' AND a.batchcode <> 0) OR (@lbatchno <> '' AND a.batchno LIKE '%' + @lbatchno + '%'))
			AND ((@limportedby = '' AND a.batchcode <> 0) OR (@limportedby <> '' AND c.username LIKE '%' + @limportedby + '%'))
		) result
		ORDER BY dateimported DESC
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)

	EXEC sp_closesymmetric
END
GO

-- ---- sp_getbatchloamappingdetails ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getbatchloamappingdetails]
	-- Add the parameters for the stored procedure here
	@batchcode	Tinyint
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lbatchcode	Tinyint = @batchcode

    SELECT 
	batchno = ISNULL(b.batchno, ''),
	a.memberno, a.amount, a.subclaimtypedesc,
	a.approvalcode, a.dateavailed, 
	a.icdcode, a.remarks, a.failedremarks
	FROM tblbatchloamappingdetails a WITH(NOLOCK)
	LEFT JOIN tblbatchloamapping b WITH(NOLOCK) ON a.batchcode = b.batchcode
	WHERE a.batchcode = @lbatchcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getbatchloamappinguploads ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getbatchloamappinguploads]
	-- Add the parameters for the stored procedure here
	@statuscode	Tinyint
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lstatuscode	Tinyint = @statuscode

    SELECT 
	batchcode, 
	batchno,  
	filename, 
	statuscode, 
	uploadedby,
	uploadedbyname = ISNULL(LTRIM(RTRIM(b.username)), ''),
	requiredfields
	FROM tblbatchloamapping a WITH(NOLOCK)
	LEFT JOIN tblusers b WITH(NOLOCK) ON a.uploadedby = b.userno
	WHERE statuscode = @lstatuscode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getbatchunconfirmedmemberaccount ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getbatchunconfirmedmemberaccount] 
	-- Add the parameters for the stored procedure here

	@compcode			Int,
	@unconfiremdfrom	Smalldatetime,
	@unconfiremdto		Smalldatetime,
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lcompcode			Int					= @compcode,
			@lunconfiremdfrom	Smalldatetime		= @unconfiremdfrom,
			@lunconfiremdto		Smalldatetime		= @unconfiremdto,
			@lpageno			Int					= @pageno,
			@lrowctr			Int					= @rowctr,
			@nodata				Bit					= 0

	IF (@lcompcode = 0 AND @lunconfiremdfrom = '1/1/1900' AND @lunconfiremdto = '1/1/1900' )
			BEGIN
				SET @nodata = 1
			END

	EXEC sp_opensymmetric

	--SELECT @rowcount = COUNT(1)

	IF OBJECT_ID('#count') IS NOT NULL 
	BEGIN 
		DROP TABLE #count
	END
	
	CREATE TABLE #count
	(
	totalctr int NOT NULL
	)

	insert into #count (totalctr)
	SELECT COUNT(1)
	FROM tblunconfirmedmembers a WITH(NOLOCK)
	WHERE ((@nodata = 1 AND a.detno = 0) OR (@nodata = 0 AND a.detno <> 0))
	AND ((@lcompcode = 0 AND a.detno <> 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode ))
	AND ((@lunconfiremdfrom = '1/1/1900' AND @lunconfiremdto = '1/1/1900' AND a.detno <> 0) OR (@lunconfiremdfrom <> '1/1/1900' AND @lunconfiremdto <> '1/1/1900'
			AND a.unconfirmeddate >= @lunconfiremdfrom AND a.unconfirmeddate < DATEADD(DAY, 1, @lunconfiremdto)))
	OPTION(RECOMPILE)

	SET @rowcount = (SELECT totalctr from #count)

	IF @lpageno <= 0 or @lrowctr <= 0
	begin
		SELECT * FROM
		(
			SELECT DISTINCT a.batchno, a.compcode, a.unconfirmeddate, a.dateencoded,
			encodedbyname = ISNULL(LTRIM(RTRIM(c.username)),''),
			accountname = ISNULL(LTRIM(RTRIM(dbo.Decrypt(d.companyname))), ''),
			contractno = ISNULL(LTRIM(RTRIM(d.contractno)),'')
			FROM tblunconfirmedmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c
			OUTER APPLY (SELECT companyname, contractno FROM tblcompany d WITH(NOLOCK) WHERE a.compcode = d.compcode) d
			WHERE ((@nodata = 1 AND a.detno = 0) OR (@nodata = 0 AND a.detno <> 0))
			AND ((@lcompcode = 0 AND a.detno <> 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode ))
			AND ((@lunconfiremdfrom = '1/1/1900' AND @lunconfiremdto = '1/1/1900' AND a.detno <> 0) OR (@lunconfiremdfrom <> '1/1/1900' AND @lunconfiremdto <> '1/1/1900'
					AND a.unconfirmeddate >= @lunconfiremdfrom AND a.unconfirmeddate < DATEADD(DAY, 1, @lunconfiremdto)))
		) result
		ORDER BY dateencoded ASC
		end
	ELSE
		begin
		SELECT * FROM
		(
			SELECT DISTINCT a.batchno, a.compcode, a.unconfirmeddate, a.dateencoded,
			encodedbyname = ISNULL(LTRIM(RTRIM(c.username)),''),
			accountname = ISNULL(LTRIM(RTRIM(dbo.Decrypt(d.companyname))), ''),
			contractno = ISNULL(LTRIM(RTRIM(d.contractno)),'')
			FROM tblunconfirmedmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c
			OUTER APPLY (SELECT companyname, contractno FROM tblcompany d WITH(NOLOCK) WHERE a.compcode = d.compcode) d
			WHERE ((@nodata = 1 AND a.detno = 0) OR (@nodata = 0 AND a.detno <> 0))
			AND ((@lcompcode = 0 AND a.detno <> 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode ))
			AND ((@lunconfiremdfrom = '1/1/1900' AND @lunconfiremdto = '1/1/1900' AND a.detno <> 0) OR (@lunconfiremdfrom <> '1/1/1900' AND @lunconfiremdto <> '1/1/1900'
					AND a.unconfirmeddate >= @lunconfiremdfrom AND a.unconfirmeddate < DATEADD(DAY, 1, @lunconfiremdto)))
		) result
		ORDER BY dateencoded ASC
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)
		end

	EXEC sp_closesymmetric

END
GO

-- ---- sp_getbatchunconfirmedmembers ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getbatchunconfirmedmembers] 
	-- Add the parameters for the stored procedure here

	@batchno			Varchar(50),
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lbatchno			Varchar(50)			= @batchno,
			@lpageno			Int					= @pageno,
			@lrowctr			Int					= @rowctr


	EXEC sp_opensymmetric

	--SELECT @rowcount = COUNT(1)

	--IF OBJECT_ID('#count') IS NOT NULL 
	--BEGIN 
	--	DROP TABLE #count
	--END
	
	--CREATE TABLE #count
	--(
	--totalctr int NOT NULL
	--)

	--insert into #count (totalctr)
	--SELECT COUNT(1)
	--FROM tblunconfirmedmembers a WITH(NOLOCK)
	--WHERE a.batchno = @lbatchno
	--OPTION(RECOMPILE)

	--SET @rowcount = (SELECT totalctr from #count)

	IF @lpageno <= 0 or @lrowctr <= 0
	begin
		SELECT * FROM
		(
			SELECT a.detno,
			memberno = ISNULL(b.memberno,''),
			membername = CASE WHEN c.enhancedencryption = 1 THEN dbo.decodercontains(d.mdflog,0)
							  WHEN c.enhancedencryption = 0 THEN dbo.decodercontains(b.mdflog,0)
							  ELSE dbo.decodercontains(b.mdflog,0)
						 END
			FROM tblunconfirmedmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT mdflog, memberno FROM tblmembers b WITH(NOLOCK) WHERE a.membercode = b.membercode) b
			OUTER APPLY (SELECT enhancedencryption FROM tblcompany c WITH(NOLOCK) WHERE a.compcode = c.compcode) c
			OUTER APPLY (SELECT mdflog FROM tblmembernames d WITH(NOLOCK) WHERE a.membercode = d.membercode) d
			WHERE a.batchno = @lbatchno
		) result
		ORDER BY membername ASC
		end
	ELSE
		begin
		SELECT * FROM
		(
			SELECT a.detno,
			memberno = ISNULL(b.memberno,''),
			membername = CASE WHEN c.enhancedencryption = 1 THEN dbo.decodercontains(d.mdflog,0)
							  WHEN c.enhancedencryption = 0 THEN dbo.decodercontains(b.mdflog,0)
							  ELSE dbo.decodercontains(b.mdflog,0)
						 END
			FROM tblunconfirmedmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT mdflog, memberno FROM tblmembers b WITH(NOLOCK) WHERE a.membercode = b.membercode) b
			OUTER APPLY (SELECT enhancedencryption FROM tblcompany c WITH(NOLOCK) WHERE a.compcode = c.compcode) c
			OUTER APPLY (SELECT mdflog FROM tblmembernames d WITH(NOLOCK) WHERE a.membercode = d.membercode) d
			WHERE a.batchno = @lbatchno
		) result
		ORDER BY membername ASC
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)
		end

	EXEC sp_closesymmetric

END
GO

-- ---- sp_getbillbatchcancelclaims ----
CREATE PROCEDURE [dbo].[sp_getbillbatchcancelclaims] --'H210100018'
	-- Add the parameters for the stored procedure here
	
	@billno	Varchar(50)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lbillno	Varchar(50) = @billno

	EXEC sp_opensymmetric

    SELECT a.claimcode, a.claimreceived, a.dateavailed, a.datedischarged,
	a.membercode, a.membertype, a.dateencoded,
	billno = LTRIM(RTRIM(a.billno)),
	caseno = LTRIM(RTRIM(a.caseno)),
	memberno = LTRIM(RTRIM(a.memberno)),
	membername = dbo.Decrypt(a.membername),
	contractno = ISNULL(LTRIM(RTRIM(f.contractno)), ''),
	companyname = dbo.Decrypt(a.companyname),
	claimtypecode = ISNULL(LTRIM(RTRIM(c.recordcode)), ''), 
	claimtypedesc = ISNULL(LTRIM(RTRIM(c.description)), ''), 
	providername = ISNULL(LTRIM(RTRIM(b.providername)), ''), 	
	icdcode = ISNULL(LTRIM(RTRIM(d.icdcode)), ''), 
	icddisease = ISNULL(LTRIM(RTRIM(d.icddisease)), ''), 
	claimstatusname = ISNULL(LTRIM(RTRIM(e.statusname)), '')  
	FROM tblclaims a WITH(NOLOCK)
	OUTER APPLY (SELECT providercode, providername FROM tblproviders b WITH(NOLOCK) WHERE a.providercode = b.providercode) b
	OUTER APPLY (SELECT recordno, recordcode, description, tablename FROM tblgentables c WITH(NOLOCK) WHERE a.claimtype = c.recordno AND c.tablename = 'CLAIMS SERVICES') c 
	OUTER APPLY (SELECT icdno, icdcode, icddisease FROM tblicdtable d WITH(NOLOCK) WHERE a.icdno = d.icdno) d 
	OUTER APPLY (SELECT statusno, statusname, statusfor FROM tblstatus e WITH(NOLOCK) WHERE a.claimstatus = e.statusno AND e.statusfor = 'CLAIMS') e
	OUTER APPLY (SELECT contractno, compcode FROM tblcompany f WITH(NOLOCK) WHERE a.compcode = f.compcode) f
	WHERE a.billno = @lbillno AND a.claimstatus = 2
	OPTION(RECOMPILE)

	EXEC sp_closesymmetric

END
GO

-- ---- sp_getcdmpmember ----
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getcdmpmember]
	-- Add the parameters for the stored procedure here

	@compcode		Int,
	@membername		Varchar(200),
	@memberno		Varchar(50),
	@cdmp			Tinyint,
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	    DECLARE @lcompcode		Int				= @compcode,
				@lmembername	Varchar(200)	= @membername,
				@lmemberno		Varchar(50)		= @memberno,
				@lcdmp			Tinyint			= @cdmp,
				@lpageno		Int					= @pageno,
				@lrowctr		Int					= @rowctr

	SELECT @rowcount = COUNT(1)
	FROM tblmembers a WITH(NOLOCK)  
	WHERE (a.compcode <> 0 AND a.compcode = @lcompcode)
		AND (a.statuscode IN(1,6))
		--AND (statuscode NOT IN(4,8)) AND (classorder = 0)
		AND ((@lcdmp = 2 AND a.membercode <> 0) OR (@lcdmp <> 2 AND a.cdmp = CAST(@lcdmp AS BIT)))
		AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(a.mdflog, 0) LIKE '%'+@lmembername+'%'))
		AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+@lmemberno+'%'))
	OPTION(RECOMPILE)

	If @pageno <= 0 or @rowctr <= 0
		BEGIN
			SELECT	a.membercode,a.effectivity, a.cdmp,
				classordername = CASE WHEN a.classorder = 0 THEN 'P' ELSE 'D' END,
				memberno = LTRIM(RTRIM(a.memberno)), 
				membername = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.mdflog, 0), '')))
			 FROM tblmembers a WITH(NOLOCK)
			 WHERE (a.compcode <> 0 AND a.compcode = @lcompcode)
				AND (a.statuscode IN(1,6))
				AND ((@lcdmp = 2 AND a.membercode <> 0) OR (@lcdmp <> 2 AND a.cdmp = CAST(@lcdmp AS BIT)))
				AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(a.mdflog, 0) LIKE '%'+@lmembername+'%'))
				AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+@lmemberno+'%'))
			ORDER BY dbo.decodercontains(a.mdflog, 0) ASC				
		END
	ELSE
		BEGIN
			SELECT	a.membercode,a.effectivity, a.cdmp,
				classordername = CASE WHEN a.classorder = 0 THEN 'P' ELSE 'D' END,
				memberno = LTRIM(RTRIM(a.memberno)), 
				membername = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.mdflog, 0), '')))
			 FROM tblmembers a WITH(NOLOCK)
			 WHERE (a.compcode <> 0 AND a.compcode = @lcompcode)
				AND (a.statuscode IN(1,6))
				--AND (statuscode NOT IN(4,8)) AND (classorder = 0)
				AND ((@lcdmp = 2 AND a.membercode <> 0) OR (@lcdmp <> 2 AND a.cdmp = CAST(@lcdmp AS BIT)))
				AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(a.mdflog, 0) LIKE '%'+@lmembername+'%'))
				AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+@lmemberno+'%'))
			ORDER BY dbo.decodercontains(a.mdflog, 0) ASC		
			OFFSET ((@lpageno - 1) * @lrowctr) ROWS
			FETCH NEXT @lrowctr ROWS ONLY
			OPTION(RECOMPILE)
		END
END



GO

-- ---- sp_getcdmpmemberlist ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getcdmpmemberlist]
	-- Add the parameters for the stored procedure here

	@compcode		Int,
	@membername		Varchar(200),
	@memberno		Varchar(50)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	    DECLARE @lcompcode		Int				= @compcode,
				@lmembername	Varchar(200)	= @membername,
				@lmemberno		Varchar(50)		= @memberno
	EXEC sp_opensymmetric

	SELECT	a.membercode,a.effectivity, a.cdmp,
			classordername = CASE WHEN a.classorder = 0 THEN 'P' ELSE 'D' END,
			memberno = LTRIM(RTRIM(a.memberno)), 
			membername = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.mdflog, 0), '')))
			FROM tblmembers a WITH(NOLOCK)
			WHERE (a.compcode <> 0 AND a.compcode = @lcompcode)
			AND (a.statuscode IN(1,6))
			AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(a.mdflog, 0) LIKE '%'+@lmembername+'%'))
			AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+@lmemberno+'%'))
		ORDER BY dbo.decodercontains(a.mdflog, 0) ASC	

	OPTION(RECOMPILE)
		
	EXEC sp_closesymmetric		
END



GO

-- ---- sp_getcdmpmemberv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getcdmpmemberv2]
	-- Add the parameters for the stored procedure here

	@compcode		Int,
	@membername		Varchar(200),
	@memberno		Varchar(50),
	@cdmp			Tinyint,
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	    DECLARE @lcompcode		Int				= @compcode,
				@lmembername	Varchar(200)	= @membername,
				@lmemberno		Varchar(50)		= @memberno,
				@lcdmp			Tinyint			= @cdmp,
				@lpageno		Int					= @pageno,
				@lrowctr		Int					= @rowctr

	SELECT @rowcount = COUNT(1)
	FROM tblmembers a WITH(NOLOCK)  
	OUTER APPLY (SELECT enhancedencryption FROM tblcompany f WITH(NOLOCK) WHERE a.compcode = f.compcode) f
	OUTER APPLY (SELECT mdflog, flog, llog, miname, suffix  FROM tblmembernames aa WITH(NOLOCK) WHERE a.membercode = aa.membercode) aa
	WHERE (a.compcode <> 0 AND a.compcode = @lcompcode)
		AND (a.statuscode IN(1,6))
		--AND (statuscode NOT IN(4,8)) AND (classorder = 0)
		AND ((@lcdmp = 2 AND a.membercode <> 0) OR (@lcdmp <> 2 AND a.cdmp = CAST(@lcdmp AS BIT)))
		AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(IIF(f.enhancedencryption = 0,a.mdflog, aa.mdflog), 0) LIKE '%'+@lmembername+'%'))
		AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+@lmemberno+'%'))
	OPTION(RECOMPILE)

	If @pageno <= 0 or @rowctr <= 0
		BEGIN
			SELECT	a.membercode,a.effectivity, a.cdmp,
				classordername = CASE WHEN a.classorder = 0 THEN 'P' ELSE 'D' END,
				memberno = LTRIM(RTRIM(a.memberno)), 
				membername = LTRIM(RTRIM(ISNULL(dbo.decodercontains(IIF(f.enhancedencryption = 0,a.mdflog, aa.mdflog), 0), '')))
			 FROM tblmembers a WITH(NOLOCK)
			 OUTER APPLY (SELECT enhancedencryption FROM tblcompany f WITH(NOLOCK) WHERE a.compcode = f.compcode) f
			 OUTER APPLY (SELECT mdflog, flog, llog, miname, suffix  FROM tblmembernames aa WITH(NOLOCK) WHERE a.membercode = aa.membercode) aa
			 WHERE (a.compcode <> 0 AND a.compcode = @lcompcode)
				AND (a.statuscode IN(1,6))
				AND ((@lcdmp = 2 AND a.membercode <> 0) OR (@lcdmp <> 2 AND a.cdmp = CAST(@lcdmp AS BIT)))
				AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(IIF(f.enhancedencryption = 0,a.mdflog, aa.mdflog), 0) LIKE '%'+@lmembername+'%'))
				AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+@lmemberno+'%'))
			ORDER BY dbo.decodercontains(a.mdflog, 0) ASC				
		END
	ELSE
		BEGIN
			SELECT	a.membercode,a.effectivity, a.cdmp,
				classordername = CASE WHEN a.classorder = 0 THEN 'P' ELSE 'D' END,
				memberno = LTRIM(RTRIM(a.memberno)), 
				membername = LTRIM(RTRIM(ISNULL(dbo.decodercontains(IIF(f.enhancedencryption = 0,a.mdflog, aa.mdflog), 0), '')))
			 FROM tblmembers a WITH(NOLOCK)
			 OUTER APPLY (SELECT enhancedencryption FROM tblcompany f WITH(NOLOCK) WHERE a.compcode = f.compcode) f
			 OUTER APPLY (SELECT mdflog, flog, llog, miname, suffix  FROM tblmembernames aa WITH(NOLOCK) WHERE a.membercode = aa.membercode) aa
			 WHERE (a.compcode <> 0 AND a.compcode = @lcompcode)
				AND (a.statuscode IN(1,6))
				--AND (statuscode NOT IN(4,8)) AND (classorder = 0)
				AND ((@lcdmp = 2 AND a.membercode <> 0) OR (@lcdmp <> 2 AND a.cdmp = CAST(@lcdmp AS BIT)))
				AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(IIF(f.enhancedencryption = 0,a.mdflog, aa.mdflog), 0) LIKE '%'+@lmembername+'%'))
				AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+@lmemberno+'%'))
			ORDER BY dbo.decodercontains(a.mdflog, 0) ASC		
			OFFSET ((@lpageno - 1) * @lrowctr) ROWS
			FETCH NEXT @lrowctr ROWS ONLY
			OPTION(RECOMPILE)
		END
END



GO

-- ---- sp_getclaimreimrequirements ----
CREATE   PROCEDURE [dbo].[sp_getclaimreimrequirements]
	-- Add the parameters for the stored procedure here
	
	@billcode		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    SELECT detno, billcode, requirementcode, remarks, postedby, dateposted 
	FROM tblclaimreimrequirements
	WHERE billcode = @billcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getclaimsbillingrequestv2 ----
CREATE PROCEDURE [dbo].[sp_getclaimsbillingrequestv2] --1,20
	-- Add the parameters for the stored procedure here
	
	@status			Varchar(20),
	@billno			Varchar(20),
	@payableto		Varchar(150),
	@payablename	Varchar(150),
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lstatus			Varchar(20)		= @status,
			@lbillno			Varchar(20)		= @billno,
			@lpayableto			Varchar(150)	= @payableto,
			@lpayablename		Varchar(150)	= @payablename,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lsearchbilltype	VARCHAR(10)		= ''

	
	EXEC sp_opensymmetric

	IF CHARINDEX(@lpayableto ,'HOSPITAL') > 0
	BEGIN
		SET @lsearchbilltype = '_H'
	END
	IF CHARINDEX(@lpayableto ,'DOCTOR') > 0
	BEGIN
		SET @lsearchbilltype = @lsearchbilltype + '_P'
	END
	IF CHARINDEX(@lpayableto ,'REIMBURSEMENT') > 0
	BEGIN
		SET @lsearchbilltype = @lsearchbilltype + '_R'
	END
	IF @lpayableto <> ''
	BEGIN
		SET @lsearchbilltype = @lsearchbilltype + '_'
	END


	SELECT @rowcount = COUNT(1)
	FROM tblapproveclaimbillings a WITH(NOLOCK)

	WHERE ((@lstatus = '' AND detno <> 0) OR (@lstatus <> '' AND UPPER(a.status) = @lstatus))
		AND ((@lbillno = '' AND detno <> 0) OR (@lbillno <> '' AND a.billno LIKE '%' + @lbillno + '%'))
		AND ((@lpayableto = '' AND a.detno <> 0) OR (@lpayableto <> '' AND  CHARINDEX('_'+ CAST(a.billtype AS VARCHAR(10)) +'_' ,@lsearchbilltype) > 0 ))
	OPTION(RECOMPILE)

    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		(
			 SELECT a.detno, a.billno, a.status, a.daterequested, a.datestarted, 
					a.billtype, a.noofclaims,
					billtypename = CASE WHEN a.billtype = 'H' THEN 'HOSPITAL'
										WHEN a.billtype = 'P' THEN 'DOCTOR'
										WHEN a.billtype = 'R' THEN 'REIMBURSEMENT'
										WHEN a.billtype = 'HBC' THEN ISNULL(RTRIM(LTRIM(UPPER(b.providername))), '')
									END,
					a.dateapproved,
					duration = CASE WHEN a.status = 'QUEUED' THEN '' 
									WHEN a.dateapproved = '1/1/1900' OR a.datestarted = '1/1/1900' THEN ''
									ELSE CONVERT(VARCHAR, DATEADD(SECOND, DATEDIFF(SECOND, a.datestarted, a.dateapproved), 0), 108) 
								END,
					a.vouchername
			FROM tblapproveclaimbillings a WITH(NOLOCK)
			LEFT OUTER JOIN tblproviders b WITH(NOLOCK) ON b.providercode = a.providercode

			WHERE ((@lstatus = '' AND detno <> 0) OR (@lstatus <> '' AND UPPER(a.status) = @lstatus))
				AND ((@lbillno = '' AND detno <> 0) OR (@lbillno <> '' AND a.billno LIKE '%' + @lbillno + '%'))
				AND ((@lpayableto = '' AND a.detno <> 0) OR (@lpayableto <> '' AND  CHARINDEX('_'+ CAST(a.billtype AS VARCHAR(10)) +'_' ,@lsearchbilltype) > 0 ))
				AND ((@lpayablename = '' AND detno <> 0) OR (@lpayablename <> '' AND a.vouchername LIKE '%' + @lpayablename + '%'))
		) result
		ORDER BY daterequested DESC
	ELSE
		SELECT * FROM
		(
			SELECT a.detno, a.billno, a.status, a.daterequested, a.datestarted, 
					a.billtype, a.noofclaims,
					billtypename = CASE WHEN a.billtype = 'H' THEN 'HOSPITAL'
										WHEN a.billtype = 'P' THEN 'DOCTOR'
										WHEN a.billtype = 'R' THEN 'REIMBURSEMENT'
										WHEN a.billtype = 'HBC' THEN ISNULL(RTRIM(LTRIM(UPPER(b.providername))), '')
									END,
					a.dateapproved,
					duration = CASE WHEN a.status = 'QUEUED' THEN '' 
									WHEN a.dateapproved = '1/1/1900' OR a.datestarted = '1/1/1900' THEN ''
									ELSE CONVERT(VARCHAR, DATEADD(SECOND, DATEDIFF(SECOND, a.datestarted, a.dateapproved), 0), 108) 
								END,
					a.vouchername
			FROM tblapproveclaimbillings a WITH(NOLOCK)
			LEFT OUTER JOIN tblproviders b WITH(NOLOCK) ON b.providercode = a.providercode

			WHERE ((@lstatus = '' AND detno <> 0) OR (@lstatus <> '' AND UPPER(a.status) = @lstatus))
				AND ((@lbillno = '' AND detno <> 0) OR (@lbillno <> '' AND a.billno LIKE '%' + @lbillno + '%'))
				AND ((@lpayableto = '' AND a.detno <> 0) OR (@lpayableto <> '' AND  CHARINDEX('_'+ CAST(a.billtype AS VARCHAR(10)) +'_' ,@lsearchbilltype) > 0 ))
				AND ((@lpayablename = '' AND detno <> 0) OR (@lpayablename <> '' AND a.vouchername LIKE '%' + @lpayablename + '%'))
		) result
		ORDER BY daterequested DESC
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)

	EXEC sp_closesymmetric
END
GO

-- ---- sp_getdoctorewtdetails ----
CREATE PROCEDURE [dbo].[sp_getdoctorewtdetails]
	-- Add the parameters for the stored procedure here
	
	@doctorcode	Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldoctorcode	Int	= @doctorcode

    SELECT a.detno, a.doctorcode, a.wtaxno,
	wtax = ISNULL(LTRIM(RTRIM(b.wtaxcode)), ''),
	wtaxrate = ISNULL(b.wtaxrate, 0.00),
	a.effectivity, a.expiry,
	a.dateencoded, encodedbyname = ISNULL(c.username, '')
	FROM tbldoctorewtdetails a WITH(NOLOCK)
	OUTER APPLY (SELECT wtaxcode, wtaxrate FROM tblwtaxrates b WITH(NOLOCK) WHERE a.wtaxno = b.wtaxno) b
	OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c
	WHERE a.doctorcode = @ldoctorcode
	ORDER BY a.effectivity DESC
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getdoctorewtjournal ----
CREATE PROCEDURE [dbo].[sp_getdoctorewtjournal] --2555
	-- Add the parameters for the stored procedure here
	
	@ewtdetailsdetno	Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lewtdetailsdetno		Int		= @ewtdetailsdetno
		
	SELECT a.detno, a.ewtdetaildetno, a.datecreated, a.userno,
	description = LTRIM(RTRIM(a.description))
	FROM tbldoctorewtjournal a WITH(NOLOCK)
	WHERE a.ewtdetaildetno = @lewtdetailsdetno
	ORDER BY a.detno desc, a.datecreated desc
	OPTION(RECOMPILE)
END
GO

-- ---- sp_getemployeetypemembers ----
CREATE PROCEDURE [dbo].[sp_getemployeetypemembers] --480,'','','','',''
	-- Add the parameters for the stored procedure here
		@compcode			Int,
		@lastname			Varchar(200),
		@firstname			Varchar(200),
		@memberno			Varchar(50),
		@benefitclass		Varchar(50),
		@premiumclass		Varchar(50)
AS
BEGIN
	SET NOCOUNT ON;

    DECLARE @lcompcode			Int				= @compcode,
			@llastname			Varchar(200)	= @lastname,
			@lfirstname			Varchar(200)	= @firstname,
			@lmemberno			Varchar(50)		= @memberno,
			@lbenefitclass		Varchar(50)		= @benefitclass,
			@lpremiumclass		Varchar(50)		= @premiumclass

	SELECT * FROM
	(
		SELECT DISTINCT a.membercode,b.employeetype,
			memberno = LTRIM(RTRIM(a.memberno)), 
			membername = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.mdflog, 0), ''))),
			lastname = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.llog, 0), ''))),
			firstname = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.flog, 0), ''))),
			benefitclass = ISNULL(LTRIM(RTRIM(a.benefitclass)), ''), 
			benefitclassname = ISNULL(LTRIM(RTRIM(e.classname)), ''),
			premiumclass = ISNULL(LTRIM(RTRIM(a.premiumclass)), ''),
			premiumclassname = ISNULL(LTRIM(RTRIM(d.premiumclassname)), '')
			FROM tblmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT employeetype FROM tblmemberdetails b WITH(NOLOCK) WHERE a.membercode = b.membercode) b
			OUTER APPLY (SELECT contractcode, compcode, effectivity FROM tblcompanycontractyears c WITH(NOLOCK) WHERE a.compcode = c.compcode AND a.effectivity >= c.effectivity AND a.expiry <= c.expiry) c 
			OUTER APPLY (SELECT detno, contractcode, compcode, premiumclasscode, premiumclassname FROM tblcompanyclassesbilling d WITH(NOLOCK) WHERE a.compcode = d.compcode AND c.contractcode = d.contractcode AND a.premiumclass = d.premiumclasscode) d
			OUTER APPLY (SELECT detno, compcode, classcode, classname, contractcode FROM tblcompanyclasses e WITH(NOLOCK) WHERE a.compcode = e.compcode AND a.benefitclass = e.classcode AND d.contractcode = e.contractcode) AS e
			WHERE ((a.compcode <> 0 AND a.compcode = @lcompcode)
			AND (statuscode NOT IN(4,8)) AND (classorder = 0)
			AND ((@llastname = '' AND a.membercode <> 0) OR (@llastname <> '' AND dbo.decodercontains(a.llog, 0) LIKE '%'+@llastname+'%'))
			AND ((@lfirstname = '' AND a.membercode <> 0) OR (@lfirstname <> '' AND dbo.decodercontains(a.flog, 0) LIKE '%'+@lfirstname+'%'))
			AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+@lmemberno+'%'))
			AND ((@lpremiumclass = '' AND a.membercode <> 0) OR (@lpremiumclass <> '' AND a.premiumclass LIKE '%'+@lpremiumclass+'%'))
			AND ((@lbenefitclass = '' AND a.membercode <> 0) OR (@lbenefitclass <> '' AND a.benefitclass LIKE '%'+@lbenefitclass+'%')))
	) result
	ORDER BY membername
	OPTION(RECOMPILE)
END
GO

-- ---- sp_getfranchiseuserauditlevel ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getfranchiseuserauditlevel] 

	@recordcode Int

AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @lrecordcode	Int = @recordcode

	SELECT a.detno, a.recordcode, a.userno, 
	usercode = ISNULL(LTRIM(RTRIM(b.usercode)), ''), 
	username = ISNULL(LTRIM(RTRIM(b.username)), ''), 
	departmentname = ISNULL(LTRIM(RTRIM(c.locationname)), '')
	FROM tblfranchiseuserauditlevel a WITH(NOLOCK)
	OUTER APPLY (SELECT usercode, username, departmentno FROM tblusers b WITH(NOLOCK) WHERE a.userno = b.userno) b
	OUTER APPLY (SELECT locationcode, locationname FROM tbllocations c WITH(NOLOCK) WHERE b.departmentno = c.locationcode) c
	WHERE a.recordcode <> 0 AND a.recordcode = @lrecordcode
	ORDER BY b.username
	OPTION(RECOMPILE)


END
GO

-- ---- sp_getgentablesv2 ----
CREATE   PROCEDURE [dbo].[sp_getgentablesv2] --'CLAIMS SERVICES','',0
	-- Add the parameters for the stored procedure here
	@tablename	Varchar(50),
	@recordcode	Varchar(50),
	@parentcode	Int
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@ltablename		Varchar(50)	= @tablename,
			@lrecordcode	Varchar(50)	= @recordcode,
			@lparentcode	Int			= @parentcode

    -- Insert statements for procedure here
	SELECT a.detno, a.recordno, a.amount, a.parentcode, a.required, a.sortorder, a.datecreated, a.createdby, a.archive, a.rowmarker,
	recordcode = LTRIM(RTRIM(a.recordcode)),
	description = LTRIM(RTRIM(a.description)),
	tablename = LTRIM(RTRIM(a.tablename)),
	createdbyname = ISNULL(LTRIM(RTRIM(b.username)), '')
	FROM tblgentables a WITH(NOLOCK)
	LEFT JOIN tblusers b WITH(NOLOCK) ON a.createdby = b.userno
	WHERE ((a.tablename = @ltablename)
	AND ((@lrecordcode = '' AND a.detno <> 0) OR (@lrecordcode <> '' AND a.recordcode = @lrecordcode))
	AND ((@lparentcode = 0 AND a.detno <> 0) OR (@lparentcode <> 0 AND a.parentcode = @lparentcode)))
	ORDER BY a.recordno
	OPTION(RECOMPILE)
END
GO

-- ---- sp_getgentablesv3 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getgentablesv3] --'CLAIMS SERVICES','',0, 0
	-- Add the parameters for the stored procedure here
	@tablename	Varchar(50),
	@recordcode	Varchar(50),
	@parentcode	Int,
	@sortby		Int = 0
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@ltablename		Varchar(50)	= @tablename,
			@lrecordcode	Varchar(50)	= @recordcode,
			@lparentcode	Int			= @parentcode,
			@lsortby		Int			= @sortby

    -- Insert statements for procedure here
	SELECT a.detno, a.recordno, a.amount, a.parentcode, a.required, a.sortorder, a.datecreated, a.createdby, a.archive, a.rowmarker,
	recordcode = LTRIM(RTRIM(a.recordcode)),
	description = LTRIM(RTRIM(a.description)),
	tablename = LTRIM(RTRIM(a.tablename)),
	createdbyname = ISNULL(LTRIM(RTRIM(b.username)), '')
	FROM tblgentables a WITH(NOLOCK)
	OUTER APPLY (SELECT b.userno, b.username FROM tblusers b WITH(NOLOCK) WHERE a.createdby = b.userno) AS b
	WHERE ((a.tablename = @ltablename)
	AND ((@lrecordcode = '' AND a.detno <> 0) OR (@lrecordcode <> '' AND a.recordcode = @lrecordcode))
	AND ((@lparentcode = 0 AND a.detno <> 0) OR (@lparentcode <> 0 AND a.parentcode = @lparentcode)))
	ORDER BY
		CASE @lsortby
			WHEN 0 THEN a.recordno
			WHEN 1 THEN a.sortorder
			WHEN 2 THEN a.detno
			WHEN 3 THEN a.description
		END ASC
	OPTION(RECOMPILE)
END
GO

-- ---- sp_getloaipreportv4 ----
CREATE PROCEDURE [dbo].[sp_getloaipreportv4] --134631

	@loacode	Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lloacode	Int = @loacode

	DECLARE @lcheckedby Varchar(100) = '',
			@lcheckedbyno Int		 = 0

	SET @lcheckedby = (SELECT signatoryname FROM tblsignatories WHERE modulename = 'CASES' AND reportname = 'IP LOA' AND signatorytype = 4)
	SET @lcheckedbyno = (SELECT signatorycode FROM tblsignatories WHERE modulename = 'CASES' AND reportname = 'IP LOA' AND signatorytype = 4)

	EXEC sp_opensymmetric

	SELECT a.loacode, a.loano, a.loadate, a.dateavailed, a.datedischarged,
	a.remarks, a.planname, a.procedures, a.otherexclusions, a.philhealth, 
	membername = dbo.Decrypt(a.membername), a.gender, a.birthdate, 
	a.loaamount, a.doctorfee, a.admittingtext,
	age = CAST(DATEDIFF(DAY, CAST(a.birthdate AS DATE), CAST(GETDATE() AS DATE))/365.26 AS INT),
	companyname = dbo.Decrypt(a.companyname),
	providername = ISNULL(b.providername, ''),
	telephone = ISNULL(b.telephone, ''),
	fax = ISNULL(b.fax, ''),
	providercontact = ISNULL(c.contactname, ''),
	providertelephone = ISNULL(c.telephone, ''),
	providerfax = ISNULL(c.fax, ''),
	department = ISNULL(c.department, ''),
	cardnumber = ISNULL(d.cardnumber, ''),
	effectivity = ISNULL(d.effectivity, '1/1/1900'),
	expiry = ISNULL(d.expiry, '1/1/1900'),
	principalname = dbo.Decrypt(a.principalname),
	prinbirthdate = ISNULL(e.birthdate, '1/1/1900'),
	prinage = IIF(a.principalcode <> 0, CAST(DATEDIFF(DAY, CAST(ISNULL(e.birthdate, '1/1/1900') AS DATE), CAST(GETDATE() AS DATE))/365.26 AS INT), 0),
	relation = ISNULL(d.relation, ''),
	icddisease = ISNULL(f.icddisease, ''),
	productcode = IIF(a.compcode <> 0, 'CORPORATE', ISNULL(h.productline, '')),
	doctorname = ISNULL(i.doctorname, ''),
	providergroup = ISNULL((SELECT TOP 1 providergroup = 
					STUFF((SELECT DISTINCT ', ' + ISNULL(LTRIM(RTRIM(xx.groupcode)),'')
							FROM tblcompanybenefitplan zz WITH(NOLOCK)
							OUTER APPLY (SELECT groupcode FROM tblprovidergroups x WITH(NOLOCK) WHERE zz.programtype = x.groupno) xx
							WHERE zz.compcode = a.compcode AND zz.contractcode = ISNULL(j.contractcode, 0) AND zz.classcode = d.benefitclass
							FOR XML PATH('')), 1, 2, '')
					FROM tblcompanybenefitplan z WITH(NOLOCK)
					OUTER APPLY (SELECT groupcode FROM tblprovidergroups x WITH(NOLOCK) WHERE z.programtype = x.groupno) x
					WHERE z.compcode = a.compcode AND z.contractcode = ISNULL(j.contractcode, 0) AND z.classcode = d.benefitclass				
					GROUP BY x.groupcode), ''),
	preparedby = ISNULL(k.username, ''),
	approvedby = ISNULL(l.username, ''),
	checkedby =  ISNULL(@lcheckedby, ''),
	endorsements = ISNULL(RTRIM(LTRIM(a.endorsements)), ''),
	hbamount = ISNULL(a.hbamount, 0.00),
	pfamount = ISNULL(a.pfamount, 0.00),
	totallimit = ISNULL(a.totallimit, 0.00),
	coinsurance = CASE WHEN m.coinsurance <> 0.00 THEN 1 ELSE 0 END,
	deductible = CASE WHEN m.deductible <> 0.00 THEN 1 ELSE 0 END,
	roomname = ISNULL(n.description, ''),
	roomtype = a.roomtype,
	preparedbysign = ISNULL(k.digitalsignature, ''),
	checkedbysign = ISNULL(o.digitalsignature, '')
	FROM tblloas a WITH(NOLOCK)
	OUTER APPLY (SELECT providername, telephone, fax FROM tblproviders b WITH(NOLOCK) WHERE a.providercode = b.providercode) b
	OUTER APPLY (SELECT department, contactname, telephone, fax FROM tblprovidercontacts c WITH(NOLOCK) WHERE a.providercode = c.providercode AND c.selectedemail = 1 AND c.selected = 1) c
	OUTER APPLY (SELECT cardnumber, effectivity, expiry, relation, benefitclass FROM tblmembers d WITH(NOLOCK) WHERE a.membercode = d.membercode) d
	OUTER APPLY (SELECT birthdate FROM tblmembers e WITH(NOLOCK) WHERE a.principalcode <> 0 AND a.principalcode = e.membercode) e
	OUTER APPLY (SELECT icddisease FROM tblicdtable f WITH(NOLOCK) WHERE a.icdno = f.icdno) f
	OUTER APPLY (SELECT productcode FROM tblcompanyclasses g WITH(NOLOCK) WHERE g.compcode = 0 AND d.benefitclass = g.classcode AND g.contractcode = 0 AND g.templatetype = 2) g
	OUTER APPLY (SELECT productline FROM tblproductlines h WITH(NOLOCK) WHERE g.productcode = h.productcode) h
	OUTER APPLY (SELECT doctorname FROM tbldoctors i WITH(NOLOCK) WHERE a.doctorcode = i.doctorcode) i
	OUTER APPLY (SELECT contractcode FROM tblcompanycontractyears j WITH(NOLOCK) WHERE a.compcode = j.compcode AND d.effectivity >= j.effectivity AND d.expiry <= j.expiry) j
	OUTER APPLY (SELECT username, digitalsignature FROM tblusers k WITH(NOLOCK) WHERE a.encodedby = k.userno) k
	OUTER APPLY (SELECT username FROM tblusers l WITH(NOLOCK) WHERE a.approvedby = l.userno) l
	OUTER APPLY (SELECT coinsurance, deductible FROM tblcompanybenefitplan m WITH(NOLOCK) WHERE a.plancode = m.plancode) m
	OUTER APPLY (SELECT detno, description FROM tblgentables n WITH(NOLOCK) WHERE a.roomtype = n.detno AND n.tablename = 'ROOM') n
	OUTER APPLY (SELECT digitalsignature FROM tblusers o WITH(NOLOCK) WHERE @lcheckedbyno = o.userno) o
	WHERE a.loacode = @lloacode
	OPTION(RECOMPILE)

	EXEC sp_closesymmetric

END

GO

-- ---- sp_getloaopipreportv3 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getloaopipreportV3] 
	-- Add the parameters for the stored procedure here
	
	@loacode	Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lloacode	Int = @loacode

	EXEC sp_opensymmetric

    SELECT a.loacode, a.loano, a.memberno, 
	membername	= CASE
				WHEN k.enhancedencryption = 0 THEN ISNULL(dbo.Decrypt(a.membername), '')
				WHEN k.enhancedencryption = 1 THEN ISNULL(dbo.decodercontains(l.mdflog, 0),'')
				WHEN k.enhancedencryption IS NULL AND a.compcode = 0 THEN ISNULL(dbo.Decrypt(a.membername), '')
				ELSE ''
			END, 
	a.coveredfrom, a.coveredto, a.birthdate, a.roomtype, 
	a.loadate, a.dateapproved, a.datedue,
	a.loaamount, a.creditedamount, a.doctorname, 
	a.providercode, a.icdno, a.admittingtext, 
	a.procedures, a.remarks, a.philhealth, 
	a.otherexclusions, a.controlno, companyname = dbo.Decrypt(a.companyname),
	ISNULL(b.providername, '') AS providername,
	ISNULL(b.telephone, '') AS telephone,
	ISNULL(b.streetaddress, '') AS streetaddress,
	ISNULL(f.locationname, '') AS cityname,
	ISNULL(g.locationname, '') AS provincename,
	ISNULL(h.locationname, '') AS regionname,
	ISNULL(c.description, '') AS roomname,
	ISNULL(d.icdcode, '') AS icdcode, 
	ISNULL(d.icddisease, '') AS icddisease, 
	ISNULL(e.specialization, '') AS doctorspecialization,
	ISNULL(i.username, '') preparedbyname,
	ISNULL(j.gender, '') AS gender,
	effectivity = ISNULL(j.effectivity, '1/1/1900'),
	expiry = ISNULL(j.expiry, '1/1/1900'),
	a.endorsements, a.healthcareprograms, a.consultationtype,
	ISNULL(LTRIM(RTRIM(n.recordcode)), '') AS subclaimtypecode,
	ISNULL(LTRIM(RTRIM(n.description)), '') AS subclaimtypedesc
	FROM tblloas a WITH(NOLOCK)
	OUTER APPLY (SELECT providercode, providername, telephone, streetaddress, citycode, provincecode, regcode FROM tblproviders b WITH(NOLOCK) WHERE a.providercode = b.providercode)b  
	OUTER APPLY (SELECT detno, description FROM tblgentables c WITH(NOLOCK) WHERE a.roomtype = c.detno) c
	OUTER APPLY (SELECT icdno, icdcode, icddisease FROM tblicdtable d WITH(NOLOCK) WHERE a.icdno = d.icdno) d 
	OUTER APPLY (SELECT doctorcode, specialization FROM tbldoctorspecialization e WITH(NOLOCK) WHERE a.doctorcode = e.doctorcode) e  
	OUTER APPLY (SELECT locationcode, locationname, parentcode FROM tbllocations f WITH(NOLOCK) WHERE b.citycode = f.locationcode) f
	OUTER APPLY (SELECT locationcode, locationname, parentcode FROM tbllocations g WITH(NOLOCK) WHERE b.provincecode = g.locationcode) g
	OUTER APPLY (SELECT locationcode, locationname, parentcode FROM tbllocations h WITH(NOLOCK) WHERE b.regcode = h.locationcode) h
	OUTER APPLY (SELECT userno, username FROM tblusers i WITH(NOLOCK) WHERE a.encodedby = i.userno) i
	OUTER APPLY (SELECT membercode, gender, effectivity, expiry FROM tblmembers j WITH(NOLOCK) WHERE a.membercode = j.membercode) j
	OUTER APPLY (SELECT enhancedencryption FROM tblcompany k WITH(NOLOCK) WHERE a.compcode = k.compcode) k
	OUTER APPLY (SELECT mdflog, flog, llog, miname, suffix  FROM tblmembernames l WITH(NOLOCK) WHERE a.membercode = l.membercode) l
	OUTER APPLY (SELECT recordcode, description FROM tblgentables m WITH(NOLOCK) WHERE a.claimtype = m.detno AND m.tablename = 'CLAIMS SERVICES' AND a.claimtype <> 0) m
	OUTER APPLY (SELECT description, recordcode FROM tblgentables n WITH(NOLOCK) WHERE a.subclaimtype = n.detno AND n.tablename = 'SUB CLAIM TYPE' AND n.recordcode = m.recordcode AND a.subclaimtype <> 0) n
	WHERE a.loacode = @lloacode
	OPTION(RECOMPILE)

	EXEC sp_closesymmetric

END
GO

-- ---- sp_getmascdmpfilepath ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getmascdmpfilepath]
AS
BEGIN
	SET NOCOUNT ON;

	EXEC sp_opensymmetric

    -- Insert statements for procedure here
	SELECT cdmpmedicaldeclarationpath, cdmpcurrentmedicationpath, cdmphealthcoachappointmentspath,
		cdmpnutritioncounsellingpath, cdmpresourcecenterpath, cdmphomelaboratoryexampath
	FROM tblsettingsweb


	EXEC sp_closesymmetric

END




GO

-- ---- sp_getmemberledgerv3 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getmemberledgerv3] --7234, '', 'ABIGPA', '', '', 0, '', '', 0, 1, 2, 20
	-- Add the parameters for the stored procedure here

	@compcode			Int,
	@memberno			Varchar(20),
	@membername			Varchar(100),
	@membertype			Varchar(20),
	@benefitclass		Varchar(20),
	@premiumclass		Varchar(20),
	@statuscode			Int,
	@effectivityfrom	Smalldatetime,
	@effectivityto		Smalldatetime,
	@policydivision		Int,
	@classorder			Int,
	@viewtype			Tinyint,
	@employeeno			Varchar(20),
	@dctno				Tinyint,
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lcompcode			Int					= @compcode,
			@lmemberno			Varchar(20)			= @memberno,
			@lmembername		Varchar(100)		= LTRIM(RTRIM(UPPER(@membername))),
			@lmembertype		Varchar(20)			= @membertype,
			@lbenefitclass		Varchar(20)			= @benefitclass,
			@lpremiumclass		Varchar(20)			= @premiumclass,
			@lstatuscode		Int					= @statuscode,
			@leffectivityfrom	Smalldatetime		= @effectivityfrom,
			@leffectivityto		Smalldatetime		= @effectivityto,
			@lpolicydivision	Int					= @policydivision,
			@lclassorder		Int					= @classorder,
			@lviewtype			Tinyint				= @viewtype,
			@lemployeeno		Varchar(20)			= @employeeno,
			@ldctno				Tinyint				= @dctno,
			@lpageno			Int					= @pageno,
			@lrowctr			Int					= @rowctr,
			@nodata				Bit					= 0

	IF (@lcompcode = 0 AND  @lmemberno = '' AND @lmembername = ''  AND @lmembertype = '' AND @lbenefitclass = ''
		AND @leffectivityfrom = '1/1/1900' AND @leffectivityto = '1/1/1900' AND @lstatuscode = 0 AND @lpolicydivision = 0 AND @lclassorder = 0)
			BEGIN
				SET @nodata = 1
			END
	
	DECLARE @decodemember Varchar(200) = '"*'+REPLACE(LTRIM(RTRIM(dbo.decodercontains(@lmembername, 1))), ')', ' ')+'*"'
	--DECLARE @decodemember Varchar(200) = LTRIM(RTRIM(dbo.decodercontains(UPPER(@lmembername), 1)))

	EXEC sp_opensymmetric

	--SELECT @rowcount = COUNT(1)

	IF OBJECT_ID('#count') IS NOT NULL 
	BEGIN 
		DROP TABLE #count
	END
	
	CREATE TABLE #count
	(
	totalctr int NOT NULL
	)

	insert into #count (totalctr)
	SELECT COUNT(1)
	FROM tblmembers a WITH(NOLOCK)
	OUTER APPLY (SELECT dependentcoveragetype FROM tblmemberdetails j WITH(NOLOCK) WHERE a.membercode = j.membercode) AS j
	WHERE (((@nodata = 1 AND a.membercode = 0) OR (@nodata = 0 AND a.membercode <> 0 AND a.membertype <> 'R' ))
	AND ((@lcompcode = 0 AND a.membercode <> 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode ))
	AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+LTRIM(RTRIM(@lmemberno))+'%'))
	AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND CONTAINS(a.mdflog, @decodemember)))
	--AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(a.mdflog, 0) LIKE '%' + @lmembername + '%'))
	AND ((@lstatuscode = 0 AND a.membercode <> 0) OR (@lstatuscode <> 0 AND a.statuscode = @lstatuscode))
	AND ((@lpolicydivision = 0 AND a.membercode <> 0) OR (@lpolicydivision <> 0 AND a.policydivision = @lpolicydivision))
	AND ((@lclassorder = 0 AND a.membercode <> 0) OR (@lclassorder <> 0 AND a.classorder = @lclassorder - 1))
	AND ((@lmembertype = '' AND a.membercode <> 0) OR (@lmembertype <> '' AND a.membercategory = @lmembertype))
	AND ((@lbenefitclass = '' AND a.membercode <> 0) OR (@lbenefitclass <> '' AND a.benefitclass = @lbenefitclass))
	AND ((@lpremiumclass = '' AND a.membercode <> 0) OR (@lpremiumclass <> '' AND a.premiumclass = @lpremiumclass))
	AND ((@lemployeeno = '' AND a.membercode <> 0) OR (@lemployeeno <> '' AND a.employeeno LIKE '%'+LTRIM(RTRIM(@lemployeeno))+'%'))
	AND ((@leffectivityfrom = '1/1/1900' AND a.membercode <> 0) OR ((@leffectivityfrom <> '1/1/1900' AND @leffectivityto <> '1/1/1900') AND (CAST(a.effectivity AS DATE) >= CAST(@leffectivityfrom AS DATE) AND CAST(a.effectivity AS DATE) <= CAST(@leffectivityto AS DATE))))
	AND ((@lviewtype = 1 AND a.membercode <> 0) OR (@lviewtype = 2 AND a.classorder = 0)))
	AND ((@ldctno = 0 AND a.membercode <> 0) OR (@ldctno <> 0 AND j.dependentcoveragetype = @ldctno))
	OPTION(RECOMPILE)

	SET @rowcount = (SELECT totalctr from #count)

	IF @lpageno <= 0 or @lrowctr <= 0
	begin
		SELECT * FROM
		(
			SELECT a.membercode, a.compcode, a.classorder, a.effectivity, a.expiry, a.renewal, a.origeffectivity, a.inactivedate, a.terminationdate,
			a.coveredfrom, a.coveredto, classordername = IIF(a.classorder = 0, 'P', 'D'),
			a.principalcode, a.policydivision, a.birthdate, a.civilstatus,a.dateencoded, a.membertype, a.specialrate, a.plancode,
			memberno = LTRIM(RTRIM(a.memberno)),
			--membername = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.mdflog, 0), ''))),
			membername = LTRIM(RTRIM(dbo.Decrypt(a.membername))),
			--lastname = LTRIM(RTRIM(ISNULL(dbo.decrypt(a.lastname), ''))),
			--firstname = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.flog, 0), ''))),
			--miname = LTRIM(RTRIM(ISNULL(CONVERT(VARCHAR(100), DECRYPTBYKEY(a.miname)), ''))),
			--suffix = LTRIM(RTRIM(a.suffix)),
			cardnumber = LTRIM(RTRIM(a.cardnumber)),
			gender = LTRIM(RTRIM(a.gender)),
			age = CAST(datediff(day, cast(a.birthdate as date), cast(getdate() as date))/365.26 as int), 
			membercategory = LTRIM(RTRIM(a.membercategory)),
			employeeno = LTRIM(RTRIM(a.employeeno)),
			benefitclass = LTRIM(RTRIM(a.benefitclass)),
			premiumclass = LTRIM(RTRIM(a.premiumclass)),
			statusname = ISNULL(LTRIM(RTRIM(b.statusname)), ''), 
			statusintial = ISNULL(LTRIM(RTRIM(b.initial)), ''), 
			newrenewal = CASE WHEN a.statuscode = 5 THEN 'T' WHEN a.renewal = 1 THEN 'R' WHEN a.renewal = 0 THEN 'N' ELSE '' END,
			encodedbyname = ISNULL(LTRIM(RTRIM(c.username)),''), 
			--companyname = LTRIM(RTRIM(ISNULL(dbo.decoder(d.ldflog, 0), ''))),
			divisionname = ISNULL(LTRIM(RTRIM(e.divisionname)),''), 
			billingschedule = CASE WHEN a.billingschedule = 1 THEN 'MONTHLY' WHEN a.billingschedule = 2 THEN 'QUARTERLY' WHEN a.billingschedule = 3 THEN 'SEMI-ANNUAL' WHEN a.billingschedule = 4 THEN 'ANNUAL' ELSE '' END,
			membertypedesc = ISNULL(LTRIM(RTRIM(f.description)), ''),
			civilstatusname = CASE WHEN a.civilstatus = 3 AND a.gender = 'M' THEN 'WIDOWER' ELSE ISNULL(LTRIM(RTRIM(g.description)), '') END,
			contractcode = ISNULL(h.contractcode, 0),
			a.nonmember,
			cardgenerated = ISNULL(l.batchdate, '1/1/1900'),
			dependentcoveragetype = ISNULL(LTRIM(RTRIM(k.description)), '')
			FROM tblmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT statusname, initial FROM tblstatus b WITH(NOLOCK) WHERE statusfor = 'MEMBER' AND a.statuscode = b.statusno) AS b
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) AS c
			--OUTER APPLY (SELECT ldflog FROM tblcompany d WITH(NOLOCK) WHERE a.compcode = d.compcode) AS d
			OUTER APPLY (SELECT divisionname FROM tblcompanydivision e WITH(NOLOCK) WHERE a.compcode = e.compcode AND a.policydivision = e.divisioncode) AS e
			OUTER APPLY (SELECT description FROM tblmembertypes f WITH(NOLOCK) WHERE a.membercategory = f.membertype) AS f
			OUTER APPLY (SELECT description FROM tblgentables g WITH(NOLOCK) WHERE a.civilstatus = g.recordno AND g.tablename = 'CIVILSTATUS') AS g
			OUTER APPLY (SELECT contractcode FROM tblcompanycontractyears h WITH(NOLOCK) WHERE a.compcode = h.compcode AND a.effectivity >= h.effectivity AND a.expiry <= h.expiry) h
			OUTER APPLY (SELECT batchdate FROM tblcompanycards l WITH(NOLOCK) WHERE a.compcode = l.compcode AND l.batchno <> '' AND a.cardbatchno = l.batchno) AS l
			OUTER APPLY (SELECT dependentcoveragetype FROM tblmemberdetails j WITH(NOLOCK) WHERE a.membercode = j.membercode) AS j
			OUTER APPLY (SELECT description FROM tblgentables k WITH(NOLOCK) WHERE j.dependentcoveragetype = k.recordno AND k.tablename = 'DEPENDENT COVERAGE TYPE') AS k
			WHERE (((@nodata = 1 AND a.membercode = 0) OR (@nodata = 0 AND a.membercode <> 0 AND a.membertype <> 'R' ))
			AND ((@lcompcode = 0 AND a.membercode <> 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode ))
			AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+LTRIM(RTRIM(@lmemberno))+'%'))
			AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND CONTAINS(a.mdflog, @decodemember)))
			--AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(a.mdflog, 0) LIKE '%' + @lmembername + '%'))
			AND ((@lstatuscode = 0 AND a.membercode <> 0) OR (@lstatuscode <> 0 AND a.statuscode = @lstatuscode))
			AND ((@lpolicydivision = 0 AND a.membercode <> 0) OR (@lpolicydivision <> 0 AND a.policydivision = @lpolicydivision))
			AND ((@lclassorder = 0 AND a.membercode <> 0) OR (@lclassorder <> 0 AND a.classorder = @lclassorder - 1))
			AND ((@lmembertype = '' AND a.membercode <> 0) OR (@lmembertype <> '' AND a.membercategory = @lmembertype))
			AND ((@lbenefitclass = '' AND a.membercode <> 0) OR (@lbenefitclass <> '' AND a.benefitclass = @lbenefitclass))
			AND ((@lpremiumclass = '' AND a.membercode <> 0) OR (@lpremiumclass <> '' AND a.premiumclass = @lpremiumclass))
			AND ((@lemployeeno = '' AND a.membercode <> 0) OR (@lemployeeno <> '' AND a.employeeno LIKE '%'+LTRIM(RTRIM(@lemployeeno))+'%'))
			AND ((@leffectivityfrom = '1/1/1900' AND a.membercode <> 0) OR ((@leffectivityfrom <> '1/1/1900' AND @leffectivityto <> '1/1/1900') AND (CAST(a.effectivity AS DATE) >= CAST(@leffectivityfrom AS DATE) AND CAST(a.effectivity AS DATE) <= CAST(@leffectivityto AS DATE))))
			AND ((@lviewtype = 1 AND a.membercode <> 0) OR (@lviewtype = 2 AND a.classorder = 0)))
			AND ((@ldctno = 0 AND a.membercode <> 0) OR (@ldctno <> 0 AND j.dependentcoveragetype = @ldctno))
		) result
		ORDER BY membername
		end
	ELSE
		begin
		SELECT * FROM
		(
			SELECT a.membercode, a.compcode, a.classorder, a.effectivity, a.expiry, a.renewal, a.origeffectivity, a.inactivedate, a.terminationdate, 
			a.coveredfrom, a.coveredto, classordername = IIF(a.classorder = 0, 'P', 'D'),
			a.principalcode, a.policydivision, a.birthdate, a.civilstatus, a.dateencoded, a.membertype,	a.specialrate, a.plancode,
			memberno = LTRIM(RTRIM(a.memberno)),
			--membername = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.mdflog, 0), ''))),
			membername = LTRIM(RTRIM(dbo.Decrypt(a.membername))),
			--lastname = LTRIM(RTRIM(ISNULL(dbo.decrypt(a.lastname), ''))),
			--firstname = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.flog, 0), ''))),
			--miname = LTRIM(RTRIM(ISNULL(CONVERT(VARCHAR(100), DECRYPTBYKEY(a.miname)), ''))),
			--suffix = LTRIM(RTRIM(a.suffix)),
			cardnumber = LTRIM(RTRIM(a.cardnumber)),
			gender = LTRIM(RTRIM(a.gender)),
			age = CAST(datediff(day, cast(a.birthdate as date), cast(getdate() as date))/365.26 as int), 
			membercategory = LTRIM(RTRIM(a.membercategory)),
			employeeno = LTRIM(RTRIM(a.employeeno)),
			benefitclass = LTRIM(RTRIM(a.benefitclass)),
			premiumclass = LTRIM(RTRIM(a.premiumclass)),
			statusname = ISNULL(LTRIM(RTRIM(b.statusname)), ''), 
			statusintial = ISNULL(LTRIM(RTRIM(b.initial)), ''), 
			newrenewal = CASE WHEN a.statuscode = 5 THEN 'T' WHEN a.renewal = 1 THEN 'R' WHEN a.renewal = 0 THEN 'N' ELSE '' END,
			encodedbyname = ISNULL(LTRIM(RTRIM(c.username)),''), 
			--companyname = LTRIM(RTRIM(ISNULL(dbo.decoder(d.ldflog, 0), ''))),
			divisionname = ISNULL(LTRIM(RTRIM(e.divisionname)),''), 
			billingschedule = CASE WHEN a.billingschedule = 1 THEN 'MONTHLY' WHEN a.billingschedule = 2 THEN 'QUARTERLY' WHEN a.billingschedule = 3 THEN 'SEMI-ANNUAL' WHEN a.billingschedule = 4 THEN 'ANNUAL' ELSE '' END,
			membertypedesc = ISNULL(LTRIM(RTRIM(f.description)), ''),
			civilstatusname = CASE WHEN a.civilstatus = 3 AND a.gender = 'M' THEN 'WIDOWER' ELSE ISNULL(LTRIM(RTRIM(g.description)), '') END,
			contractcode = ISNULL(h.contractcode, 0),
			a.nonmember,
			cardgenerated = ISNULL(l.batchdate, '1/1/1900'),
			dependentcoveragetype = ISNULL(LTRIM(RTRIM(k.description)), '')
			FROM tblmembers a WITH(NOLOCK)
			OUTER APPLY (SELECT statusname, initial FROM tblstatus b WITH(NOLOCK) WHERE statusfor = 'MEMBER' AND a.statuscode = b.statusno) AS b
			OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) AS c
			--OUTER APPLY (SELECT ldflog FROM tblcompany d WITH(NOLOCK) WHERE a.compcode = d.compcode) AS d
			OUTER APPLY (SELECT divisionname FROM tblcompanydivision e WITH(NOLOCK) WHERE a.compcode = e.compcode AND a.policydivision = e.divisioncode) AS e
			OUTER APPLY (SELECT description FROM tblmembertypes f WITH(NOLOCK) WHERE a.membercategory = f.membertype) AS f
			OUTER APPLY (SELECT description FROM tblgentables g WITH(NOLOCK) WHERE a.civilstatus = g.recordno AND g.tablename = 'CIVILSTATUS') AS g
			OUTER APPLY (SELECT contractcode FROM tblcompanycontractyears h WITH(NOLOCK) WHERE a.compcode = h.compcode AND a.effectivity >= h.effectivity AND a.expiry <= h.expiry) h
			OUTER APPLY (SELECT batchdate FROM tblcompanycards l WITH(NOLOCK) WHERE a.compcode = l.compcode AND l.batchno <> '' AND a.cardbatchno = l.batchno) AS l
			OUTER APPLY (SELECT dependentcoveragetype FROM tblmemberdetails j WITH(NOLOCK) WHERE a.membercode = j.membercode) AS j
			OUTER APPLY (SELECT description FROM tblgentables k WITH(NOLOCK) WHERE j.dependentcoveragetype = k.recordno AND k.tablename = 'DEPENDENT COVERAGE TYPE') AS k
			WHERE (((@nodata = 1 AND a.membercode = 0) OR (@nodata = 0 AND a.membercode <> 0 AND a.membertype <> 'R'))
			AND ((@lcompcode = 0 AND a.membercode <> 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode ))
			AND ((@lmemberno = '' AND a.membercode <> 0) OR (@lmemberno <> '' AND a.memberno LIKE '%'+LTRIM(RTRIM(@lmemberno))+'%'))
			AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND CONTAINS(a.mdflog, @decodemember)))
			--AND ((@lmembername = '' AND a.membercode <> 0) OR (@lmembername <> '' AND dbo.decodercontains(a.mdflog, 0) LIKE '%' + @lmembername + '%'))
			AND ((@lstatuscode = 0 AND a.membercode <> 0) OR (@lstatuscode <> 0 AND a.statuscode = @lstatuscode))
			AND ((@lpolicydivision = 0 AND a.membercode <> 0) OR (@lpolicydivision <> 0 AND a.policydivision = @lpolicydivision))
			AND ((@lclassorder = 0 AND a.membercode <> 0) OR (@lclassorder <> 0 AND a.classorder = @lclassorder - 1))
			AND ((@lmembertype = '' AND a.membercode <> 0) OR (@lmembertype <> '' AND a.membercategory = @lmembertype))
			AND ((@lbenefitclass = '' AND a.membercode <> 0) OR (@lbenefitclass <> '' AND a.benefitclass = @lbenefitclass))
			AND ((@lpremiumclass = '' AND a.membercode <> 0) OR (@lpremiumclass <> '' AND a.premiumclass = @lpremiumclass))			
			AND ((@lemployeeno = '' AND a.membercode <> 0) OR (@lemployeeno <> '' AND a.employeeno LIKE '%'+LTRIM(RTRIM(@lemployeeno))+'%'))
			AND ((@leffectivityfrom = '1/1/1900' AND a.membercode <> 0) OR ((@leffectivityfrom <> '1/1/1900' AND @leffectivityto <> '1/1/1900') AND (CAST(a.effectivity AS DATE) >= CAST(@leffectivityfrom AS DATE) AND CAST(a.effectivity AS DATE) <= CAST(@leffectivityto AS DATE))))
			AND ((@lviewtype = 1 AND a.membercode <> 0) OR (@lviewtype = 2 AND a.classorder = 0)))
			AND ((@ldctno = 0 AND a.membercode <> 0) OR (@ldctno <> 0 AND j.dependentcoveragetype = @ldctno))
		) result
		ORDER BY membername
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)
		end

	EXEC sp_closesymmetric

END
GO

-- ---- sp_getmemberportalsettingsjournal ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE     PROCEDURE [dbo].[sp_getmemberportalsettingsjournal]

	@memberportalsettingsno Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @l@memberportalsettingsno Int = @memberportalsettingsno

	SELECT a.detno, a.memberportalsettingsno, a.dateencoded, a.required, a.encodedby,
	description = LTRIM(RTRIM(a.description)),
	username = ISNULL(LTRIM(RTRIM(b.username)), '')
	FROM tblmemberportalsettingsjournal a WITH(NOLOCK)
	OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
	WHERE a.memberportalsettingsno = @l@memberportalsettingsno
	ORDER BY a.dateencoded DESC, a.detno DESC
	OPTION(RECOMPILE)

END

GO

-- ---- sp_getmemberportalsettingsv4 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE     PROCEDURE [dbo].[sp_getmemberportalsettingsv4] 
	-- Add the parameters for the stored procedure here
	
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	--DEClARE @lcompcode	Int		= @compcode,
	--		@lstatus	TinyInt	= @status

    SELECT a.detno, a.compcode, a.showpremiuminfo, a.showcivilstatus, a.datecreated, a.homogendependenttopup, a.principaltopupindepcpd,
	a.principaltopup, a.independentcpd, a.companyemployeeshare, a.dependentcoveragetype,  a.topupcoverage,  
	a.dependenttopup, a.showconfirm,
	companyname = ISNULL(dbo.decoder(b.ldflog,0), ''),
	contractno = ISNULL(b.contractno, ''),
	encodedbyname = ISNULL(c.username, '')
	
	FROM tblmemberportalsettings a WITH(NOLOCK)
	OUTER APPLY (SELECT ldflog, contractno FROM tblcompany b WITH(NOLOCK) WHERE a.compcode = b.compcode) b
	OUTER APPLY (SELECT username FROM tblusers c WITH(NOLOCK) WHERE a.createdby = c.userno) c
	ORDER BY a.datecreated DESC
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getmembersbenefitplans ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getmembersbenefitplans]
	@compcode INT,
	@contractcode INT,
    @soacode INT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

DECLARE @cols NVARCHAR(MAX) = ''
DECLARE @sql  NVARCHAR(MAX) = ''

--column headers
SELECT @cols += ',' + QUOTENAME(limitcode + ' | ' + planname)
FROM (
    SELECT DISTINCT d.recordcode AS limitcode, c.planname
    FROM tblmembers a
    OUTER APPLY (SELECT compcode, contractcode, classcode FROM tblcompanyclasses b WITH(NOLOCK)
        WHERE b.classcode = a.benefitclass AND b.compcode = @compcode AND b.contractcode = @contractcode) b
    OUTER APPLY (SELECT planname, sobplancode, compcode, contractcode, classcode, membertype, limitsetup FROM tblcompanybenefitplan c WITH(NOLOCK) 
        WHERE b.classcode = c.classcode AND c.compcode = @compcode AND c.contractcode = @contractcode AND membertype LIKE '%'+ LTRIM(RTRIM(a.membercategory)) +'%' ) c
    OUTER APPLY (SELECT recordno, recordcode, tablename FROM tblgentables d WITH(NOLOCK) 
        WHERE c.limitsetup = d.recordno AND d.tablename = 'PLAN LIMIT') d
    WHERE a.membercode IN (SELECT membercode FROM tblsoapremiummembers WHERE compcode = @compcode AND soacode = @soacode)
        AND a.compcode = @compcode
) AS plans
ORDER BY limitcode

SET @cols = STUFF(@cols, 1, 1, '')

--Wrap columns
DECLARE @colsWithISNULL NVARCHAR(MAX) = ''
SELECT @colsWithISNULL += ', ISNULL(' + QUOTENAME(limitcode + ' | ' + planname) + ', 0) AS ' + QUOTENAME(limitcode + ' | ' + planname)
FROM (
    SELECT DISTINCT d.recordcode AS limitcode, c.planname
    FROM tblmembers a
    OUTER APPLY (SELECT compcode, contractcode, classcode FROM tblcompanyclasses b WITH(NOLOCK)
        WHERE b.classcode = a.benefitclass AND b.compcode = @compcode AND b.contractcode = @contractcode) b
    OUTER APPLY (SELECT planname, sobplancode, compcode, contractcode, classcode, membertype, limitsetup FROM tblcompanybenefitplan c WITH(NOLOCK) 
        WHERE b.classcode = c.classcode AND c.compcode = @compcode AND c.contractcode = @contractcode AND membertype LIKE '%'+ LTRIM(RTRIM(a.membercategory)) +'%' ) c
    OUTER APPLY (SELECT recordno, recordcode, tablename FROM tblgentables d WITH(NOLOCK) 
        WHERE c.limitsetup = d.recordno AND d.tablename = 'PLAN LIMIT') d
    WHERE a.membercode IN (SELECT membercode FROM tblsoapremiummembers WHERE compcode = @compcode AND soacode = @soacode)
        AND a.compcode = @compcode
) AS plans
ORDER BY limitcode

SET @colsWithISNULL = STUFF(@colsWithISNULL, 1, 2, '')

--Final dynamic pivot query
SET @sql = '
SELECT membercode, memberno, ' + @colsWithISNULL + '
FROM (
    SELECT 
        a.membercode,
        a.memberno,
        d.recordcode + '' | '' + c.planname AS plan_col,
        ISNULL(c.limitamount, 0) AS limitamount
    FROM tblmembers a

    OUTER APPLY (SELECT compcode, contractcode, classcode FROM tblcompanyclasses b WITH(NOLOCK)
        WHERE b.classcode = a.benefitclass AND b.compcode = ' + CAST(@compcode AS VARCHAR) + ' AND b.contractcode = ' + CAST(@contractcode AS VARCHAR) + ') b
    OUTER APPLY (SELECT planname, sobplancode, compcode, contractcode, classcode, membertype, limitamount, limitsetup FROM tblcompanybenefitplan c WITH(NOLOCK) 
        WHERE b.classcode = c.classcode AND c.compcode = ' + CAST(@compcode AS VARCHAR) + ' AND c.contractcode = ' + CAST(@contractcode AS VARCHAR) + ' AND membertype LIKE ''%''+ LTRIM(RTRIM(a.membercategory)) +''%'') c
    OUTER APPLY (SELECT recordno, recordcode, tablename FROM tblgentables d WITH(NOLOCK) 
        WHERE c.limitsetup = d.recordno AND d.tablename = ''PLAN LIMIT'') d
    WHERE a.membercode IN (SELECT membercode FROM tblsoapremiummembers WHERE compcode = ' + CAST(@compcode AS VARCHAR) + ' AND soacode = ' + CAST(@soacode AS VARCHAR) + ')
        AND a.compcode = ' + CAST(@compcode AS VARCHAR) + '
) AS src
PIVOT (
    SUM(limitamount)
    FOR plan_col IN (' + @cols + ')
) AS pvt'

EXEC sp_executesql @sql

END
GO

-- ---- sp_getmembertermination ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getmembertermination] 
	-- Add the parameters for the stored procedure here
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    -- Insert statements for procedure here
	SELECT terminationno, compcode, membercode
	FROM tblmembertermination
	WHERE processed = 0 AND effectivity <= GETDATE()

END
GO

-- ---- sp_getmemberuploadbatchv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getmemberuploadbatchv2]
	@portalcode	Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	Int	= @portalcode

    -- Insert statements for procedure here
	SELECT a.batchcode, a.compcode, a.contractcode,
	batchno = ISNULL(LTRIM(RTRIM(b.batchno)), '')
	FROM tblportalupload a WITH(NOLOCK)
	LEFT JOIN tblmemberuploadbatch b WITH(NOLOCK) ON a.batchcode = b.batchcode
	WHERE a.portalcode = @lportalcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getmemberuploaddetailsv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getmemberuploaddetailsv2]
	@batchcode	Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lbatchcode	Int	= @batchcode

    -- Insert statements for procedure here
	SELECT a.effectivity, a.contractcode, a.compcode, a.membercode, a.modalfrom, modalto, a.premiumamt, a.nafamt, a.dafamt,
	premiumclass = LTRIM(RTRIM(ISNULL(a.premiumclass, a.premiumclass))),
	memberno = LTRIM(RTRIM(a.memberno)),
	dummymemberno = LTRIM(RTRIM(a.dummymemberno)),
	membertype = ISNULL(LTRIM(RTRIM(b.membercategory)), ''),
	birthdate = ISNULL(b.birthdate, 1/1/1900),
	billclassdetno = ISNULL(c.detno, 0),
	billingschedule = CAST(ISNULL(c.billingschedule, b.billingschedule) AS INT)
	FROM tblmemberuploaddetails a WITH(NOLOCK)
	LEFT JOIN tblmembers b WITH(NOLOCK) ON a.membercode = b.membercode
	LEFT JOIN tblcompanyclassesbilling c WITH(NOLOCK) ON a.compcode = c.compcode AND a.contractcode = c.contractcode AND ISNULL(b.premiumclass, a.premiumclass) = c.premiumclasscode
	
	WHERE batchcode = @lbatchcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getmrfreporttemplate ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getmrfreporttemplate]
	-- Add the parameters for the stored procedure here

	@templatetype Int
AS
BEGIN
	-- SET NOCOUNT WITH(NOLOCK) WHERE added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ltemplatetype	Int	 = @templatetype

	SELECT templateno, 
	templatename = LTRIM(RTRIM(templatename)), 
	templatedatatype = LTRIM(RTRIM(templatedatatype)),  
	templatetype, required
	FROM tblmrfreporttemplate WITH(NOLOCK)
	WHERE templatetype = @ltemplatetype
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getportaluploadtransmittallogsv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getportaluploadtransmittallogsv2]
	-- Add the parameters for the stored procedure here
	
	@compcode		Int,
	@portalno		Varchar(50),
	@uploadedfrom	Smalldatetime,
	@uploadedto		Smalldatetime,
	@statuscode		Int,
	@uploadtype		Varchar(20),
	@sortfield		Varchar(50),
	@sorttype		Varchar(5)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lcompcode		Int				= @compcode,
			@lportalno		Varchar(50)		= @portalno,
			@luploadedfrom	Smalldatetime	= @uploadedfrom,
			@luploadedto	Smalldatetime	= @uploadedto,
			@lstatuscode	Int				= @statuscode,
			@luploadtype	Varchar(20)		= @uploadtype,
			@lsortfield		Varchar(50)		= @sortfield,
			@lsorttype		Varchar(5)		= @sorttype,
			@lnodata		Bit				= 0

	IF (@lcompcode = 0 AND @lportalno = '' AND @luploadedfrom = '1/1/1900' AND @luploadedto = '1/1/1900' AND @lcompcode = 0 AND @luploadtype = '')
		BEGIN
			SET @lnodata = 1
		END

	SELECT a.portalcode, portalno = LTRIM(RTRIM(a.portalno)), 
		a.compcode,
		contractno = ISNULL(LTRIM(RTRIM(c.contractno)), ''),
		companyname = ISNULL(LTRIM(RTRIM(dbo.decoder(c.ldflog, 0))), ''),
		filename = LTRIM(RTRIM(a.filename)), 
		duration = LTRIM(RTRIM(a.duration)),
		a.uploaded,
		a.statuscode, statusname = ISNULL(LTRIM(RTRIM(b.statusname)), ''), 
		a.datequeued, a.datenotified, a.dateencoded,
		a.percentage, 
		--a.datesra3started, a.datesra2started, a.datesra1started,
		uploadtype = LTRIM(RTRIM(a.uploadtype)),
		encodedbyname = ISNULL(LTRIM(RTRIM(d.username)), '')
	FROM tblportalupload a WiTH(NOLOCK)
		OUTER APPLY (SELECT statusno, statusname, statusfor FROM tblstatus b WiTH(NOLOCK) WHERE b.statusfor = 'PORTAL UPLOAD' AND a.statuscode = b.statusno) b
		OUTER APPLY (SELECT compcode, ldflog, contractno FROM tblcompany c WITH(NOLOCK) WHERE a.compcode = c.compcode) c
		OUTER APPLY (SELECT userno, username FROM tblusers d WITH(NOLOCK) WHERE a.encodedby = d.userno) d
	WHERE ((@lnodata = 1 AND a.portalcode = 0) OR (@lnodata = 0 AND ( 
		(((@lcompcode = 0 AND a.portalcode <> 0) OR (@lcompcode <> 0 AND a.compcode = @lcompcode))
		AND ((@lstatuscode = 0 AND a.portalcode <> 0) OR (@lstatuscode <> 0 AND ((@lstatuscode = 1 AND a.statuscode IN (4,9)) OR
																			 (@lstatuscode = 2 AND a.statuscode IN (1,2,3,7,8)) OR
																			 (@lstatuscode = 3 AND a.statuscode = 5) OR
																			 (@lstatuscode = 4 AND a.statuscode = 6))))
		AND ((@lportalno = '' AND a.portalcode <> 0) OR (@lportalno <> '' AND a.portalno LIKE '%'+@lportalno+'%'))
		AND ((@luploadedfrom = '1/1/1900' AND a.portalcode <> 0) OR ((@luploadedfrom <> '1/1/1900' AND @luploadedto <> '1/1/1900') 
			AND (CAST(a.dateencoded AS DATE) >= CAST(@luploadedfrom AS DATE) AND CAST(a.dateencoded AS DATE) <= CAST(@luploadedto AS DATE))))))
		AND ((@luploadtype = '' AND a.portalcode <> 0) OR (@luploadtype <> '' AND a.uploadtype = @luploadtype))
		))
	ORDER BY 	
		CASE WHEN @lsorttype = 'desc' and @lsortfield = 'dateencoded' THEN dateencoded END DESC,
		CASE WHEN @lsorttype = 'asc' and @lsortfield = 'dateencoded' THEN dateencoded END ASC,
		
		CASE WHEN @lsorttype = 'desc' and @lsortfield = 'uploaded' THEN uploaded END DESC,
		CASE WHEN @lsorttype = 'asc' and @lsortfield = 'uploaded' THEN uploaded END ASC,
			
		CASE WHEN @lsorttype = 'desc' and @lsortfield = 'portalno' THEN portalno END DESC,
		CASE WHEN @lsorttype = 'asc' and @lsortfield = 'portalno' THEN portalno END ASC,
				
		CASE WHEN @lsorttype = 'desc' and @lsortfield = 'duration' THEN duration END DESC,
		CASE WHEN @lsorttype = 'asc' and @lsortfield = 'duration' THEN duration END ASC
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getprintasobillinginvoice ----
CREATE   PROCEDURE [dbo].[sp_getprintasobillinginvoice]
	-- Add the parameters for the stored procedure here
	
	@soacode		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lsoacode		Int				= @soacode

	SELECT a.soacode, a.soano, a.soadate, a.soadue, a.soaamount, a.statuscode, a.dategenerated, 
	a.compcode, a.paidamount, a.coveredfrom, a.coveredto,
	contractno = LTRIM(RTRIM(ISNULL(b.contractno, ''))),
	companyname = LTRIM(RTRIM(ISNULL(dbo.decoder(b.ldflog, 0), ''))),
	tinno = LTRIM(RTRIM(ISNULL(b.tinno, ''))),
	streetaddress = LTRIM(RTRIM(ISNULL(b.streetaddress, ''))),
	cityname = LTRIM(RTRIM(ISNULL(f.locationname, ''))),
	provincename = LTRIM(RTRIM(ISNULL(g.locationname, ''))),
	statusname = LTRIM(RTRIM(ISNULL(c.statusname, ''))),
	initial = ISNULL(e.initial, 0),
	effectivity = ISNULL(e.effectivity, 1/1/1900),
	expiry = ISNULL(e.expiry, 1/1/1900),
	generatedbyname = LTRIM(RTRIM(ISNULL(d.username, ''))),
	soatype = ISNULL(LTRIM(RTRIM(h.description)), ''),
	accountcode = ISNULL(LTRIM(RTRIM(b.accountcode)), ''),
	agentname = CASE WHEN ISNULL(i.agenttype, 0) = 10 THEN ISNULL(LTRIM(RTRIM(i.organizationname)), '') ELSE ISNULL(LTRIM(RTRIM(i.agentname)), '') END,
	billingaddressee = ISNULL(LTRIM(RTRIM(j.billingaddressee)), ''), 
	designation = ISNULL(LTRIM(RTRIM(j.designation)), ''), 
	billingschedule = CASE WHEN a.billingschedule = 1 THEN 'M - MONTHLY MODE' 
						   WHEN a.billingschedule = 2 THEN 'Q - QUARTERLY MODE' 
						   WHEN a.billingschedule = 3 THEN 'S - SEMI-ANNUAL MODE' 
						   WHEN a.billingschedule = 4 THEN 'A - ANNUAL MODE' END
	FROM tblsoaaccounts a WITH(NOLOCK)
	OUTER APPLY (SELECT contractno, ldflog, tinno, streetaddress, billingschedule, citycode, provincecode, accountcode FROM tblcompany b WITH(NOLOCK) WHERE a.compcode = b.compcode) b
	OUTER APPLY (SELECT statusname FROM tblstatus c WITH(NOLOCK) WHERE a.statuscode = c.statusno AND c.statusfor = 'SOA') c
	OUTER APPLY (SELECT username FROM tblusers d WITH(NOLOCK) WHERE a.generatedby = d.userno) d
	OUTER APPLY (SELECT initial, effectivity, expiry FROM tblcompanycontractyears e WITH(NOLOCK) WHERE a.contractcode = e.contractcode) e
	OUTER APPLY (SELECT locationname FROM tbllocations f WITH(NOLOCK) WHERE b.citycode = f.locationcode) f
	OUTER APPLY (SELECT locationname FROM tbllocations g WITH(NOLOCK) WHERE b.provincecode = g.locationcode) g
	OUTER APPLY (SELECT description FROM tblgentables h WITH(NOLOCK) WHERE h.tablename = 'SOATYPE' AND a.soatype = h.recordno) h
	OUTER APPLY (SELECT agentno FROM tblcompanyagentcommission k WITH(NOLOCK) WHERE a.compcode = k.compcode AND k.active = 1) k
	OUTER APPLY (SELECT agentno, agentname, agenttype, organizationname FROM tblagents i WITH(NOLOCK) WHERE k.agentno = i.agentno) i
	OUTER APPLY (SELECT compcode, divisioncode, defaultbilling, billingaddressee, designation FROM tblcompanydivision j WITH(NOLOCK) WHERE a.compcode = j.compcode and a.policydivision = j.divisioncode and j.defaultbilling = 1) j
	WHERE (a.soacode = @lsoacode) AND (a.billtype = 5) AND (a.soatype = 3)

END
GO

-- ---- sp_getproductlinesv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getproductlinesv2] --'',''
	-- Add the parameters for the stored procedure here
	
	@productlinecode	Varchar(50),
	@productline		Varchar(100)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lproductlinecode	Varchar(50)		= @productlinecode,
			@lproductline		Varchar(100)	= @productline


	SELECT a.productcode, a.productlinecode, a.productline, a.iorta,
	a.required, a.datecreated, a.memberportalassociation,
	encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), '')
	FROM tblproductlines a
	OUTER APPLY (SELECT userno, username FROM tblusers b WITH(NOLOCK) WHERE a.createdby = b.userno) b
	WHERE (((@lproductlinecode = '' AND a.productcode <> 0) OR (@lproductlinecode <> '' AND a.productcode LIKE '%'+@lproductlinecode+'%'))
	AND ((@lproductline = '' AND a.productcode <> 0) OR (@lproductline <> '' AND a.productline LIKE '%'+@lproductline+'%')))
	ORDER BY a.productcode DESC
	OPTION(RECOMPILE)

END

GO

-- ---- sp_getproviderledgerv2 ----
CREATE PROCEDURE [dbo].[sp_getproviderledgerv2] --0,0,0,0,'','ASIAN','','','','',1,20
	-- Add the parameters for the stored procedure here
	
	@providercode	Int,
	@providertype	Int,
	@status			Int,
	@regioncode		Int,
	@initials		Varchar(50),
	@providername	Varchar(240),
	@address		Varchar(100),
	@coordinator	Varchar(100),
	@slcode			Varchar(20),
	@industrycode	Varchar(20),
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lprovidercode		Int				= @providercode,
			@lprovidertype		Int				= @providertype,
			@lstatus			Int				= @status,
			@lregioncode		Int				= @regioncode,		
			@linitials			Varchar(50)		= @initials,
			@lprovidername		Varchar(240)	= @providername,
			@laddress			Varchar(100)	= @address,
			@lcoordinator		Varchar(100)	= @coordinator,
			@lslcode			Varchar(20)		= @slcode,
			@lindustrycode		Varchar(20)		= @industrycode,
			@lnodata			Bit				= 0,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr;

	IF (@lprovidercode = 0 AND @lprovidertype = 0 AND @lstatus = 0 AND @lregioncode = 0 AND @linitials = '' AND 
		@lprovidername = '' AND @laddress = '' AND @lcoordinator = '' AND @lslcode = '' AND @lindustrycode = '')
		BEGIN
			SET @lnodata = 1;
		END

	SELECT @rowcount = COUNT(1)

	--IF OBJECT_ID('#count') IS NOT NULL 
	--BEGIN 
	--	DROP TABLE #count
	--END
	
	--CREATE TABLE #count
	--(
	--totalctr int NOT NULL
	--)

	--insert into #count (totalctr)
	--SELECT COUNT(1)
	FROM tblproviders a WITH(NOLOCK)
	OUTER APPLY (SELECT b.locationname FROM tbllocations b (NOLOCK) WHERE a.citycode = b.locationcode) b
	OUTER APPLY (SELECT c.username FROM tblusers c (NOLOCK) WHERE a.encodedby = c.userno) c
	OUTER APPLY (SELECT d.description FROM tblgentables d (NOLOCK) WHERE a.providerlevel = d.detno) d 
	OUTER APPLY (SELECT e.locationcode, e.locationname, e.locationno FROM tbllocations e (NOLOCK) WHERE a.provincecode = e.locationcode) e 
	OUTER APPLY (SELECT f.providername FROM tblproviders f (NOLOCK) WHERE a.billedto = f.providercode) f
	OUTER APPLY (SELECT g.description FROM tblgentables g (NOLOCK) WHERE a.bank = g.detno AND g.tablename = 'BANKS') g
	WHERE (((@lnodata = 1 AND a.providercode = 0) OR (@lnodata = 0 AND a.providercode <> 0))
	AND ((@lprovidercode = 0 AND a.providercode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
	AND ((@lprovidertype = 0 AND a.providercode <> 0) OR ((@lprovidertype <> 0 AND @lprovidertype = 4 AND LTRIM(RTRIM(UPPER(a.clinictype))) LIKE '%DENTAL%')
	OR (@lprovidertype <> 0 AND @lprovidertype <> 4 AND a.providertype = @lprovidertype )))
	AND ((@lstatus = 0 AND a.providercode <> 0) OR ((@lstatus <> 0 AND @lstatus = 1 AND a.accredited = 1 ) OR (@lstatus <> 0 AND @lstatus = 2 AND a.accredited = 0)))
	AND ((@lregioncode = 0 AND a.providercode <> 0) OR (@lregioncode <> 0 AND a.regcode  = @lregioncode))
	AND ((@linitials = '' AND a.providercode <> 0) OR (@linitials <> '' AND a.initials = @linitials))
	AND ((@lprovidername = '' AND a.providercode <> 0) OR (@lprovidername <> '' AND a.providername LIKE '%'+@lprovidername+'%'))
	AND ((@laddress = '' AND a.providercode <> 0) OR ((@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%'))))
	--AND ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%')))
	--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%')))
	--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%')))
	AND ((@lcoordinator = '' AND a.providercode <> 0) OR (@lcoordinator <> '' AND a.operatorname LIKE '%'+@lcoordinator+'%'))
	AND ((@lslcode = '' AND a.providercode <> 0) OR (@lslcode <> '' AND a.slcode LIKE '%'+@lslcode+'%'))
	AND ((@lindustrycode = '' AND a.providercode <> 0) OR (@lindustrycode <> '' AND a.industrycode LIKE '%'+@lindustrycode+'%')))										
	OPTION(RECOMPILE)

	--SET @rowcount = (SELECT totalctr from #count)


    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		(
			SELECT a.providercode, a.providertype, a.providerlevel, a.billedto, a.wtaxno, 
			a.reqvolume, a.citycode, a.provincecode, a.regcode, a.zipcode, a.tinno, a.creditceiling, 
			a.dateaccredited, a.accreditrenewal, a.accredited, a.philhealth, a.creditterm, a.deactivated, 
			a.clinictype, a.encodedby, a.dateencoded, a.owned, a.wtax, a.vat, a.industrycode, a.bankacctemail, a.withada, 
			a.paymentmethod, a.paymentmethoddetail, a.rebateamount, a.rebaterate, a.calendardays,
			a.paymentbeneaddress, a.paymentbankcode, a.paymentbankaddress, a.bankcodepesonet,
			providername = LTRIM(RTRIM(a.providername)), 
			initials = LTRIM(RTRIM(a.initials)),
			operatorname = LTRIM(RTRIM(a.operatorname)), 
			telephone = LTRIM(RTRIM(a.telephone)), 
			mobile = LTRIM(RTRIM(a.mobile)),
			fax = LTRIM(RTRIM(a.fax)), 
			website = LTRIM(RTRIM(a.website)),
			emailaddress = LTRIM(RTRIM(a.emailaddress)), 
			streetaddress = LTRIM(RTRIM(a.streetaddress)),
			branchname = LTRIM(RTRIM(a.branchname)), 
			hmocontact = LTRIM(RTRIM(a.hmocontact)),
			coordinatorsched = LTRIM(RTRIM(a.coordinatorsched)), 
			penaltyfee = LTRIM(RTRIM(a.penaltyfee)),
			bankname = ISNULL(LTRIM(RTRIM(g.description)), ''),
			bankacctno = LTRIM(RTRIM(a.bankacctno)), 
			bankacctname = LTRIM(RTRIM(a.bankacctname)),
			bankacctcurr = LTRIM(RTRIM(a.bankacctcurr)), 
			bankaccttype = LTRIM(RTRIM(a.bankaccttype)), 
			bankacctreferenceno = LTRIM(RTRIM(a.bankacctreferenceno)),
			latitude = LTRIM(RTRIM(a.latitude)),
			longitude = LTRIM(RTRIM(a.longitude)),
			operatorroom = LTRIM(RTRIM(a.operatorroom)),
			cityname = ISNULL(LTRIM(RTRIM(b.locationname)), ''), 
			encodedname = ISNULL(LTRIM(RTRIM(c.username)), ''), 
			levelname = ISNULL(LTRIM(RTRIM(d.description)), ''),
			provincename = ISNULL(LTRIM(RTRIM(e.locationname)), ''),
			regionname = ISNULL(LTRIM(RTRIM(e.locationno)), ''),
			billedtoname = ISNULL(LTRIM(RTRIM(f.providername)), ''),
			mobile2 = LTRIM(RTRIM(a.mobile2)),
			a.statuscode, 
			statusname = CASE WHEN a.statuscode = 1 THEN 'ACTIVE'
							  WHEN a.statuscode = 2 THEN 'INACTIVE'
							  END,
			a.approvedby, approvedbyname = ISNULL(LTRIM(RTRIM(h.username)), ''),
			a.dateapproved
			FROM tblproviders a WITH(NOLOCK)
			OUTER APPLY (SELECT b.locationname FROM tbllocations b (NOLOCK) WHERE a.citycode = b.locationcode) b
			OUTER APPLY (SELECT c.username FROM tblusers c (NOLOCK) WHERE a.encodedby = c.userno) c
			OUTER APPLY (SELECT d.description FROM tblgentables d (NOLOCK) WHERE a.providerlevel = d.detno) d 
			OUTER APPLY (SELECT e.locationcode, e.locationname, e.locationno FROM tbllocations e (NOLOCK) WHERE a.provincecode = e.locationcode) e 
			OUTER APPLY (SELECT f.providername FROM tblproviders f (NOLOCK) WHERE a.billedto = f.providercode) f
			OUTER APPLY (SELECT g.description FROM tblgentables g (NOLOCK) WHERE a.bank = g.detno AND g.tablename = 'BANKS') g
			OUTER APPLY (SELECT username FROM tblusers h WITH(NOLOCK) WHERE a.approvedby = h.userno) h
			WHERE (((@lnodata = 1 AND a.providercode = 0) OR (@lnodata = 0 AND a.providercode <> 0))
			AND ((@lprovidercode = 0 AND a.providercode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
			AND ((@lprovidertype = 0 AND a.providercode <> 0) OR ((@lprovidertype <> 0 AND @lprovidertype = 4 AND LTRIM(RTRIM(UPPER(a.clinictype))) LIKE '%DENTAL%')
			OR (@lprovidertype <> 0 AND @lprovidertype <> 4 AND a.providertype = @lprovidertype )))
			AND ((@lstatus = 0 AND a.providercode <> 0) OR ((@lstatus <> 0 AND @lstatus = 1 AND a.accredited = 1 ) OR (@lstatus <> 0 AND @lstatus = 2 AND a.accredited = 0)))
			AND ((@lregioncode = 0 AND a.providercode <> 0) OR (@lregioncode <> 0 AND a.regcode  = @lregioncode))
			AND ((@linitials = '' AND a.providercode <> 0) OR (@linitials <> '' AND a.initials = @linitials))
			AND ((@lprovidername = '' AND a.providercode <> 0) OR (@lprovidername <> '' AND a.providername LIKE '%'+@lprovidername+'%'))
			AND ((@laddress = '' AND a.providercode <> 0) OR ((@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%'))))
			--AND ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%')))
			--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%')))
			--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%')))
			AND ((@lcoordinator = '' AND a.providercode <> 0) OR (@lcoordinator <> '' AND a.operatorname LIKE '%'+@lcoordinator+'%'))
			AND ((@lslcode = '' AND a.providercode <> 0) OR (@lslcode <> '' AND a.slcode LIKE '%'+@lslcode+'%'))
			AND ((@lindustrycode = '' AND a.providercode <> 0) OR (@lindustrycode <> '' AND a.industrycode LIKE '%'+@lindustrycode+'%')))	
		) result
		ORDER BY providername
	ELSE
		SELECT * FROM
		(
			SELECT a.providercode, a.providertype, a.providerlevel, a.billedto, a.wtaxno, 
			a.reqvolume, a.citycode, a.provincecode, a.regcode, a.zipcode, a.tinno, a.creditceiling, 
			a.dateaccredited, a.accreditrenewal, a.accredited, a.philhealth, a.creditterm, a.deactivated, 
			a.clinictype, a.encodedby, a.dateencoded, a.owned, a.wtax, a.vat, a.industrycode, a.bankacctemail, a.withada, 
			a.paymentmethod, a.paymentmethoddetail, a.rebateamount, a.rebaterate, a.calendardays,
			a.paymentbeneaddress, a.paymentbankcode, a.paymentbankaddress, a.bankcodepesonet,
			providername = LTRIM(RTRIM(a.providername)), 
			initials = LTRIM(RTRIM(a.initials)),
			operatorname = LTRIM(RTRIM(a.operatorname)), 
			telephone = LTRIM(RTRIM(a.telephone)), 
			mobile = LTRIM(RTRIM(a.mobile)),
			fax = LTRIM(RTRIM(a.fax)), 
			website = LTRIM(RTRIM(a.website)),
			emailaddress = LTRIM(RTRIM(a.emailaddress)), 
			streetaddress = LTRIM(RTRIM(a.streetaddress)),
			branchname = LTRIM(RTRIM(a.branchname)), 
			hmocontact = LTRIM(RTRIM(a.hmocontact)),
			coordinatorsched = LTRIM(RTRIM(a.coordinatorsched)), 
			penaltyfee = LTRIM(RTRIM(a.penaltyfee)),
			bankname = ISNULL(LTRIM(RTRIM(g.description)), ''),
			bankacctno = LTRIM(RTRIM(a.bankacctno)), 
			bankacctname = LTRIM(RTRIM(a.bankacctname)),
			bankacctcurr = LTRIM(RTRIM(a.bankacctcurr)), 
			bankaccttype = LTRIM(RTRIM(a.bankaccttype)), 
			bankacctreferenceno = LTRIM(RTRIM(a.bankacctreferenceno)),
			latitude = LTRIM(RTRIM(a.latitude)),
			longitude = LTRIM(RTRIM(a.longitude)),
			operatorroom = LTRIM(RTRIM(a.operatorroom)),
			cityname = ISNULL(LTRIM(RTRIM(b.locationname)), ''), 
			encodedname = ISNULL(LTRIM(RTRIM(c.username)), ''), 
			levelname = ISNULL(LTRIM(RTRIM(d.description)), ''),
			provincename = ISNULL(LTRIM(RTRIM(e.locationname)), ''),
			regionname = ISNULL(LTRIM(RTRIM(e.locationno)), ''),
			billedtoname = ISNULL(LTRIM(RTRIM(f.providername)), ''),
			mobile2 = LTRIM(RTRIM(a.mobile2)),
			a.statuscode, 
			statusname = CASE WHEN a.statuscode = 1 THEN 'ACTIVE'
							  WHEN a.statuscode = 2 THEN 'INACTIVE'
							  END,
			a.approvedby, approvedbyname = ISNULL(LTRIM(RTRIM(h.username)), ''),
			a.dateapproved
			FROM tblproviders a WITH(NOLOCK)
			OUTER APPLY (SELECT b.locationname FROM tbllocations b (NOLOCK) WHERE a.citycode = b.locationcode) b
			OUTER APPLY (SELECT c.username FROM tblusers c (NOLOCK) WHERE a.encodedby = c.userno) c
			OUTER APPLY (SELECT d.description FROM tblgentables d (NOLOCK) WHERE a.providerlevel = d.detno) d 
			OUTER APPLY (SELECT e.locationcode, e.locationname, e.locationno FROM tbllocations e (NOLOCK) WHERE a.provincecode = e.locationcode) e 
			OUTER APPLY (SELECT f.providername FROM tblproviders f (NOLOCK) WHERE a.billedto = f.providercode) f
			OUTER APPLY (SELECT g.description FROM tblgentables g (NOLOCK) WHERE a.bank = g.detno AND g.tablename = 'BANKS') g
			OUTER APPLY (SELECT username FROM tblusers h WITH(NOLOCK) WHERE a.approvedby = h.userno) h
			WHERE (((@lnodata = 1 AND a.providercode = 0) OR (@lnodata = 0 AND a.providercode <> 0))
			AND ((@lprovidercode = 0 AND a.providercode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
			AND ((@lprovidertype = 0 AND a.providercode <> 0) OR ((@lprovidertype <> 0 AND @lprovidertype = 4 AND LTRIM(RTRIM(UPPER(a.clinictype))) LIKE '%DENTAL%')
			OR (@lprovidertype <> 0 AND @lprovidertype <> 4 AND a.providertype = @lprovidertype )))
			AND ((@lstatus = 0 AND a.providercode <> 0) OR ((@lstatus <> 0 AND @lstatus = 1 AND a.accredited = 1 ) OR (@lstatus <> 0 AND @lstatus = 2 AND a.accredited = 0)))
			AND ((@lregioncode = 0 AND a.providercode <> 0) OR (@lregioncode <> 0 AND a.regcode  = @lregioncode))
			AND ((@linitials = '' AND a.providercode <> 0) OR (@linitials <> '' AND a.initials = @linitials))
			AND ((@lprovidername = '' AND a.providercode <> 0) OR (@lprovidername <> '' AND a.providername LIKE '%'+@lprovidername+'%'))
			AND ((@laddress = '' AND a.providercode <> 0) OR ((@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%'))))
			--AND ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%')))
			--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%')))
			--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%')))
			AND ((@lcoordinator = '' AND a.providercode <> 0) OR (@lcoordinator <> '' AND a.operatorname LIKE '%'+@lcoordinator+'%'))
			AND ((@lslcode = '' AND a.providercode <> 0) OR (@lslcode <> '' AND a.slcode LIKE '%'+@lslcode+'%'))
			AND ((@lindustrycode = '' AND a.providercode <> 0) OR (@lindustrycode <> '' AND a.industrycode LIKE '%'+@lindustrycode+'%')))	
		) result
		ORDER BY providername
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)

END
GO

-- ---- sp_getproviderledgerv3 ----
CREATE   PROCEDURE [dbo].[sp_getproviderledgerv3] --0,0,0,0,'','ASIAN','','','','',1,20
	-- Add the parameters for the stored procedure here
	
	@providercode	Int,
	@providertype	Int,
	@status			Int,
	@regioncode		Int,
	@initials		Varchar(50),
	@providername	Varchar(240),
	@address		Varchar(100),
	@coordinator	Varchar(100),
	@slcode			Varchar(20),
	@industrycode	Varchar(20),
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lprovidercode		Int				= @providercode,
			@lprovidertype		Int				= @providertype,
			@lstatus			Int				= @status,
			@lregioncode		Int				= @regioncode,		
			@linitials			Varchar(50)		= @initials,
			@lprovidername		Varchar(240)	= @providername,
			@laddress			Varchar(100)	= @address,
			@lcoordinator		Varchar(100)	= @coordinator,
			@lslcode			Varchar(20)		= @slcode,
			@lindustrycode		Varchar(20)		= @industrycode,
			@lnodata			Bit				= 0,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr;

	IF (@lprovidercode = 0 AND @lprovidertype = 0 AND @lstatus = 0 AND @lregioncode = 0 AND @linitials = '' AND 
		@lprovidername = '' AND @laddress = '' AND @lcoordinator = '' AND @lslcode = '' AND @lindustrycode = '')
		BEGIN
			SET @lnodata = 1;
		END

	SELECT @rowcount = COUNT(1)

	--IF OBJECT_ID('#count') IS NOT NULL 
	--BEGIN 
	--	DROP TABLE #count
	--END
	
	--CREATE TABLE #count
	--(
	--totalctr int NOT NULL
	--)

	--insert into #count (totalctr)
	--SELECT COUNT(1)
	FROM tblproviders a WITH(NOLOCK)
	OUTER APPLY (SELECT b.locationname FROM tbllocations b (NOLOCK) WHERE a.citycode = b.locationcode) b
	OUTER APPLY (SELECT c.username FROM tblusers c (NOLOCK) WHERE a.encodedby = c.userno) c
	OUTER APPLY (SELECT d.description FROM tblgentables d (NOLOCK) WHERE a.providerlevel = d.detno) d 
	OUTER APPLY (SELECT e.locationcode, e.locationname, e.locationno FROM tbllocations e (NOLOCK) WHERE a.provincecode = e.locationcode) e 
	OUTER APPLY (SELECT f.providername FROM tblproviders f (NOLOCK) WHERE a.billedto = f.providercode) f
	OUTER APPLY (SELECT g.description FROM tblgentables g (NOLOCK) WHERE a.bank = g.detno AND g.tablename = 'BANKS') g
	WHERE (((@lnodata = 1 AND a.providercode = 0) OR (@lnodata = 0 AND a.providercode <> 0))
	AND ((@lprovidercode = 0 AND a.providercode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
	AND ((@lprovidertype = 0 AND a.providercode <> 0) OR ((@lprovidertype <> 0 AND @lprovidertype = 4 AND LTRIM(RTRIM(UPPER(a.clinictype))) LIKE '%DENTAL%')
	OR (@lprovidertype <> 0 AND @lprovidertype <> 4 AND a.providertype = @lprovidertype )))
	AND ((@lstatus = 0 AND a.providercode <> 0) OR ((@lstatus <> 0 AND @lstatus = 1 AND a.accredited = 1 ) OR (@lstatus <> 0 AND @lstatus = 2 AND a.accredited = 0)))
	AND ((@lregioncode = 0 AND a.providercode <> 0) OR (@lregioncode <> 0 AND a.regcode  = @lregioncode))
	AND ((@linitials = '' AND a.providercode <> 0) OR (@linitials <> '' AND a.initials = @linitials))
	AND ((@lprovidername = '' AND a.providercode <> 0) OR (@lprovidername <> '' AND a.providername LIKE '%'+@lprovidername+'%'))
	AND ((@laddress = '' AND a.providercode <> 0) OR ((@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%'))))
	--AND ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%')))
	--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%')))
	--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%')))
	AND ((@lcoordinator = '' AND a.providercode <> 0) OR (@lcoordinator <> '' AND a.operatorname LIKE '%'+@lcoordinator+'%'))
	AND ((@lslcode = '' AND a.providercode <> 0) OR (@lslcode <> '' AND a.slcode LIKE '%'+@lslcode+'%'))
	AND ((@lindustrycode = '' AND a.providercode <> 0) OR (@lindustrycode <> '' AND a.industrycode LIKE '%'+@lindustrycode+'%')))										
	OPTION(RECOMPILE)

	--SET @rowcount = (SELECT totalctr from #count)


    If @pageno <= 0 or @rowctr <= 0
		SELECT * FROM
		(
			SELECT a.providercode, a.providertype, a.providerlevel, a.billedto, a.wtaxno, 
			a.reqvolume, a.citycode, a.provincecode, a.regcode, a.zipcode, a.tinno, a.creditceiling, 
			a.dateaccredited, a.accreditrenewal, a.accredited, a.philhealth, a.creditterm, a.deactivated, 
			a.clinictype, a.encodedby, a.dateencoded, a.owned, a.wtax, a.vat, a.industrycode, a.bankacctemail, a.withada, 
			a.paymentmethod, a.paymentmethoddetail, a.rebateamount, a.rebaterate, a.calendardays,
			a.paymentbeneaddress, a.paymentbankcode, a.paymentbankaddress, a.bankcodepesonet,
			wtaxcode = ISNULL(LTRIM(RTRIM(i.wtaxcode)), ''),
			wtaxrate = ISNULL(i.wtaxrate, 0.00),
			providername = LTRIM(RTRIM(a.providername)), 
			initials = LTRIM(RTRIM(a.initials)),
			operatorname = LTRIM(RTRIM(a.operatorname)), 
			telephone = LTRIM(RTRIM(a.telephone)), 
			mobile = LTRIM(RTRIM(a.mobile)),
			fax = LTRIM(RTRIM(a.fax)), 
			website = LTRIM(RTRIM(a.website)),
			emailaddress = LTRIM(RTRIM(a.emailaddress)), 
			streetaddress = LTRIM(RTRIM(a.streetaddress)),
			branchname = LTRIM(RTRIM(a.branchname)), 
			hmocontact = LTRIM(RTRIM(a.hmocontact)),
			coordinatorsched = LTRIM(RTRIM(a.coordinatorsched)), 
			penaltyfee = LTRIM(RTRIM(a.penaltyfee)),
			bankname = ISNULL(LTRIM(RTRIM(g.description)), ''),
			bankacctno = LTRIM(RTRIM(a.bankacctno)), 
			bankacctname = LTRIM(RTRIM(a.bankacctname)),
			bankacctcurr = LTRIM(RTRIM(a.bankacctcurr)), 
			bankaccttype = LTRIM(RTRIM(a.bankaccttype)), 
			bankacctreferenceno = LTRIM(RTRIM(a.bankacctreferenceno)),
			latitude = LTRIM(RTRIM(a.latitude)),
			longitude = LTRIM(RTRIM(a.longitude)),
			operatorroom = LTRIM(RTRIM(a.operatorroom)),
			cityname = ISNULL(LTRIM(RTRIM(b.locationname)), ''), 
			encodedname = ISNULL(LTRIM(RTRIM(c.username)), ''), 
			levelname = ISNULL(LTRIM(RTRIM(d.description)), ''),
			provincename = ISNULL(LTRIM(RTRIM(e.locationname)), ''),
			regionname = ISNULL(LTRIM(RTRIM(e.locationno)), ''),
			billedtoname = ISNULL(LTRIM(RTRIM(f.providername)), ''),
			mobile2 = LTRIM(RTRIM(a.mobile2)),
			a.statuscode, 
			statusname = CASE WHEN a.statuscode = 1 THEN 'ACTIVE'
							  WHEN a.statuscode = 2 THEN 'INACTIVE'
							  END,
			a.approvedby, approvedbyname = ISNULL(LTRIM(RTRIM(h.username)), ''),
			a.dateapproved
			FROM tblproviders a WITH(NOLOCK)
			OUTER APPLY (SELECT b.locationname FROM tbllocations b (NOLOCK) WHERE a.citycode = b.locationcode) b
			OUTER APPLY (SELECT c.username FROM tblusers c (NOLOCK) WHERE a.encodedby = c.userno) c
			OUTER APPLY (SELECT d.description FROM tblgentables d (NOLOCK) WHERE a.providerlevel = d.detno) d 
			OUTER APPLY (SELECT e.locationcode, e.locationname, e.locationno FROM tbllocations e (NOLOCK) WHERE a.provincecode = e.locationcode) e 
			OUTER APPLY (SELECT f.providername FROM tblproviders f (NOLOCK) WHERE a.billedto = f.providercode) f
			OUTER APPLY (SELECT g.description FROM tblgentables g (NOLOCK) WHERE a.bank = g.detno AND g.tablename = 'BANKS') g
			OUTER APPLY (SELECT username FROM tblusers h WITH(NOLOCK) WHERE a.approvedby = h.userno) h
			OUTER APPLY (SELECT wtaxcode, wtaxrate FROM tblwtaxrates i WITH(NOLOCK) WHERE a.wtaxno = i.wtaxno) i
			WHERE (((@lnodata = 1 AND a.providercode = 0) OR (@lnodata = 0 AND a.providercode <> 0))
			AND ((@lprovidercode = 0 AND a.providercode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
			AND ((@lprovidertype = 0 AND a.providercode <> 0) OR ((@lprovidertype <> 0 AND @lprovidertype = 4 AND LTRIM(RTRIM(UPPER(a.clinictype))) LIKE '%DENTAL%')
			OR (@lprovidertype <> 0 AND @lprovidertype <> 4 AND a.providertype = @lprovidertype )))
			AND ((@lstatus = 0 AND a.providercode <> 0) OR ((@lstatus <> 0 AND @lstatus = 1 AND a.accredited = 1 ) OR (@lstatus <> 0 AND @lstatus = 2 AND a.accredited = 0)))
			AND ((@lregioncode = 0 AND a.providercode <> 0) OR (@lregioncode <> 0 AND a.regcode  = @lregioncode))
			AND ((@linitials = '' AND a.providercode <> 0) OR (@linitials <> '' AND a.initials = @linitials))
			AND ((@lprovidername = '' AND a.providercode <> 0) OR (@lprovidername <> '' AND a.providername LIKE '%'+@lprovidername+'%'))
			AND ((@laddress = '' AND a.providercode <> 0) OR ((@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%'))))
			--AND ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%')))
			--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%')))
			--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%')))
			AND ((@lcoordinator = '' AND a.providercode <> 0) OR (@lcoordinator <> '' AND a.operatorname LIKE '%'+@lcoordinator+'%'))
			AND ((@lslcode = '' AND a.providercode <> 0) OR (@lslcode <> '' AND a.slcode LIKE '%'+@lslcode+'%'))
			AND ((@lindustrycode = '' AND a.providercode <> 0) OR (@lindustrycode <> '' AND a.industrycode LIKE '%'+@lindustrycode+'%')))	
		) result
		ORDER BY providername
	ELSE
		SELECT * FROM
		(
			SELECT a.providercode, a.providertype, a.providerlevel, a.billedto, a.wtaxno, 
			a.reqvolume, a.citycode, a.provincecode, a.regcode, a.zipcode, a.tinno, a.creditceiling, 
			a.dateaccredited, a.accreditrenewal, a.accredited, a.philhealth, a.creditterm, a.deactivated, 
			a.clinictype, a.encodedby, a.dateencoded, a.owned, a.wtax, a.vat, a.industrycode, a.bankacctemail, a.withada, 
			a.paymentmethod, a.paymentmethoddetail, a.rebateamount, a.rebaterate, a.calendardays,
			a.paymentbeneaddress, a.paymentbankcode, a.paymentbankaddress, a.bankcodepesonet,
			wtaxcode = ISNULL(LTRIM(RTRIM(i.wtaxcode)), ''),
			wtaxrate = ISNULL(i.wtaxrate, 0.00),
			providername = LTRIM(RTRIM(a.providername)), 
			initials = LTRIM(RTRIM(a.initials)),
			operatorname = LTRIM(RTRIM(a.operatorname)), 
			telephone = LTRIM(RTRIM(a.telephone)), 
			mobile = LTRIM(RTRIM(a.mobile)),
			fax = LTRIM(RTRIM(a.fax)), 
			website = LTRIM(RTRIM(a.website)),
			emailaddress = LTRIM(RTRIM(a.emailaddress)), 
			streetaddress = LTRIM(RTRIM(a.streetaddress)),
			branchname = LTRIM(RTRIM(a.branchname)), 
			hmocontact = LTRIM(RTRIM(a.hmocontact)),
			coordinatorsched = LTRIM(RTRIM(a.coordinatorsched)), 
			penaltyfee = LTRIM(RTRIM(a.penaltyfee)),
			bankname = ISNULL(LTRIM(RTRIM(g.description)), ''),
			bankacctno = LTRIM(RTRIM(a.bankacctno)), 
			bankacctname = LTRIM(RTRIM(a.bankacctname)),
			bankacctcurr = LTRIM(RTRIM(a.bankacctcurr)), 
			bankaccttype = LTRIM(RTRIM(a.bankaccttype)), 
			bankacctreferenceno = LTRIM(RTRIM(a.bankacctreferenceno)),
			latitude = LTRIM(RTRIM(a.latitude)),
			longitude = LTRIM(RTRIM(a.longitude)),
			operatorroom = LTRIM(RTRIM(a.operatorroom)),
			cityname = ISNULL(LTRIM(RTRIM(b.locationname)), ''), 
			encodedname = ISNULL(LTRIM(RTRIM(c.username)), ''), 
			levelname = ISNULL(LTRIM(RTRIM(d.description)), ''),
			provincename = ISNULL(LTRIM(RTRIM(e.locationname)), ''),
			regionname = ISNULL(LTRIM(RTRIM(e.locationno)), ''),
			billedtoname = ISNULL(LTRIM(RTRIM(f.providername)), ''),
			mobile2 = LTRIM(RTRIM(a.mobile2)),
			a.statuscode, 
			statusname = CASE WHEN a.statuscode = 1 THEN 'ACTIVE'
							  WHEN a.statuscode = 2 THEN 'INACTIVE'
							  END,
			a.approvedby, approvedbyname = ISNULL(LTRIM(RTRIM(h.username)), ''),
			a.dateapproved
			FROM tblproviders a WITH(NOLOCK)
			OUTER APPLY (SELECT b.locationname FROM tbllocations b (NOLOCK) WHERE a.citycode = b.locationcode) b
			OUTER APPLY (SELECT c.username FROM tblusers c (NOLOCK) WHERE a.encodedby = c.userno) c
			OUTER APPLY (SELECT d.description FROM tblgentables d (NOLOCK) WHERE a.providerlevel = d.detno) d 
			OUTER APPLY (SELECT e.locationcode, e.locationname, e.locationno FROM tbllocations e (NOLOCK) WHERE a.provincecode = e.locationcode) e 
			OUTER APPLY (SELECT f.providername FROM tblproviders f (NOLOCK) WHERE a.billedto = f.providercode) f
			OUTER APPLY (SELECT g.description FROM tblgentables g (NOLOCK) WHERE a.bank = g.detno AND g.tablename = 'BANKS') g
			OUTER APPLY (SELECT username FROM tblusers h WITH(NOLOCK) WHERE a.approvedby = h.userno) h
			OUTER APPLY (SELECT wtaxcode, wtaxrate FROM tblwtaxrates i WITH(NOLOCK) WHERE a.wtaxno = i.wtaxno) i
			WHERE (((@lnodata = 1 AND a.providercode = 0) OR (@lnodata = 0 AND a.providercode <> 0))
			AND ((@lprovidercode = 0 AND a.providercode <> 0) OR (@lprovidercode <> 0 AND a.providercode = @lprovidercode))
			AND ((@lprovidertype = 0 AND a.providercode <> 0) OR ((@lprovidertype <> 0 AND @lprovidertype = 4 AND LTRIM(RTRIM(UPPER(a.clinictype))) LIKE '%DENTAL%')
			OR (@lprovidertype <> 0 AND @lprovidertype <> 4 AND a.providertype = @lprovidertype )))
			AND ((@lstatus = 0 AND a.providercode <> 0) OR ((@lstatus <> 0 AND @lstatus = 1 AND a.accredited = 1 ) OR (@lstatus <> 0 AND @lstatus = 2 AND a.accredited = 0)))
			AND ((@lregioncode = 0 AND a.providercode <> 0) OR (@lregioncode <> 0 AND a.regcode  = @lregioncode))
			AND ((@linitials = '' AND a.providercode <> 0) OR (@linitials <> '' AND a.initials = @linitials))
			AND ((@lprovidername = '' AND a.providercode <> 0) OR (@lprovidername <> '' AND a.providername LIKE '%'+@lprovidername+'%'))
			AND ((@laddress = '' AND a.providercode <> 0) OR ((@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%'))
															  OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%'))))
			--AND ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (a.streetaddress LIKE '%'+@laddress+'%')))
			--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (b.locationname LIKE '%'+@laddress+'%')))
			--	OR ((@laddress = '' AND a.providercode <> 0) OR (@laddress <> '' AND (e.locationname LIKE '%'+@laddress+'%')))
			AND ((@lcoordinator = '' AND a.providercode <> 0) OR (@lcoordinator <> '' AND a.operatorname LIKE '%'+@lcoordinator+'%'))
			AND ((@lslcode = '' AND a.providercode <> 0) OR (@lslcode <> '' AND a.slcode LIKE '%'+@lslcode+'%'))
			AND ((@lindustrycode = '' AND a.providercode <> 0) OR (@lindustrycode <> '' AND a.industrycode LIKE '%'+@lindustrycode+'%')))	
		) result
		ORDER BY providername
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)

END
GO

-- ---- sp_getreimbursementrequirements ----
CREATE PROCEDURE [dbo].[sp_getreimbursementrequirements]
	-- Add the parameters for the stored procedure here

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    SELECT detno, description, createdby,
	createdbyname = ISNULL(b.username, ''), datecreated
	FROM tblgentables a WITH(NOLOCK)
	OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.createdby = b.userno) b
	WHERE tablename = 'REIMBURSEMENT REQUIREMENTS'
	ORDER BY description
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getretailapplicationdetailsv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getretailapplicationdetailsv2] --1962
	-- Add the parameters for the stored procedure here

	@applicationcode			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	DECLARE @lapplicationcode	Int	= @applicationcode

	DECLARE @KeyGUID UNIQUEIDENTIFIER 
	SET @KeyGUID = KEY_GUID('Decrypt')

	EXEC sp_opensymmetric

	SELECT a.applicationcode, a.applicationdate, a.membercode, a.statuscode, a.birthdate, a.classorder, a.billingschedule, 
	a.dateencoded, a.encodedby, a.premiumfee, a.billto, a.bmicategory, a.height, a.weight,  a.branch, a.membersince, 
	a.renewal, a.onetimefee, a.withphilhealth, a.pecwaived, a.provideraccess, a.datehired, a.annualpremiumfee, 
	a.nonpremiumfee, a.originalfee, a.originalnonfee,  a.sacode, a.medicalstatus,  a.medicalremarks ,
	a.specialrate, a.nomedicaldeclaration, a.onlineapp, a.withtelemedicine, a.discountrate, a.agentno,
	a.benefitclass, 
	benefitclassname = ISNULL(LTRIM(RTRIM(r.classname)), ''),
	a.premiumclass,
	premiumclassname = ISNULL(LTRIM(RTRIM(q.premiumclassname)), ''),
	applicationno = LTRIM(RTRIM(a.applicationno)), 
	membertype = LTRIM(RTRIM(a.membertype)), 
	--firstname = LTRIM(RTRIM(dbo.decodercontains(a.flog, 0))), 
	firstname = LTRIM(RTRIM(dbo.Decrypt(a.firstname))), 
	miname = LTRIM(RTRIM(dbo.Decrypt(a.miname))), 
	--lastname = LTRIM(RTRIM(dbo.decodercontains(a.llog, 0))), 
	lastname = LTRIM(RTRIM(dbo.Decrypt(a.lastname))), 
	suffix = LTRIM(RTRIM(a.suffix)), 
	--membername = LTRIM(RTRIM(dbo.decodercontains(a.mdflog, 0))), 	
	membername = LTRIM(RTRIM(dbo.Decrypt(a.membername))), 
	gender = LTRIM(RTRIM(a.gender)), 
	picturename = LTRIM(RTRIM(a.picturename)), 	
	telephone = LTRIM(RTRIM(a.telephone)),
	mobile = LTRIM(RTRIM(dbo.Decrypt(a.mobile))), 
	emailaddress = LTRIM(RTRIM(dbo.Decrypt(a.emailaddress))),
	civilstatus = a.civilstatus,
	civilstatusname = ISNULL(LTRIM(RTRIM(s.description)), ''),
	sssno = LTRIM(RTRIM(a.sssno)),
	tin = LTRIM(RTRIM(a.tin)), 
	employer = LTRIM(RTRIM(a.employer)), 
	monthlyfamilyincome = LTRIM(RTRIM(a.monthlyfamilyincome)),
	occupation = LTRIM(RTRIM(a.occupation)), 
	newoccupation = LTRIM(RTRIM(a.newoccupation)), 
	a.billingprovince, a.billingcity,
	billingstreet = LTRIM(RTRIM(a.billingstreet)), 
	billingcityname = ISNULL(LTRIM(RTRIM(d.locationname)), ''),
	billingcityprovince = ISNULL(LTRIM(RTRIM(e.locationname)), ''),
	zipcodebilling = LTRIM(RTRIM(a.zipcodebilling)), 
	a.homecity, a.homeprovince,
	homestreet = LTRIM(RTRIM(a.homestreet)), 
	homecityname = ISNULL(LTRIM(RTRIM(f.locationname)), ''), 	
	homeprovincename = ISNULL(LTRIM(RTRIM(g.locationname)), ''), 
	zipcodehome = LTRIM(RTRIM(a.zipcodehome)),
	bmiresult = LTRIM(RTRIM(a.bmiresult)),  	
	memberno = LTRIM(RTRIM(a.memberno)), 
	employeeno = LTRIM(RTRIM(a.employeeno)), 
	membercategory = LTRIM(RTRIM(a.membercategory)), 
	payorname = LTRIM(RTRIM(a.payorname)), 
	payortin = LTRIM(RTRIM(a.payortin)), 
	businessstyle = LTRIM(RTRIM(a.businessstyle)),
	age = CAST(DATEDIFF(DAY, CAST(a.birthdate as date), CAST(a.applicationdate as date))/365.26 as int), 
	agentname = IIF(b.agenttype = 10, ISNULL(b.organizationname, ''), ISNULL(LTRIM(RTRIM(b.agentname)), '')),	
	a.productcode,
	productlinecode = ISNULL(LTRIM(RTRIM(j.productlinecode)), ''),
	productline = ISNULL(LTRIM(RTRIM(j.productline)), ''), 
	membercategorydesc = ISNULL(LTRIM(RTRIM(k.description)), ''), 
	bmicategorydesc = ISNULL(LTRIM(RTRIM(l.description)), ''), 
	roomcategory = ISNULL(LTRIM(RTRIM(m.description)), ''), 
	branchname = ISNULL(LTRIM(RTRIM(n.locationname)), ''), 
	provideraccessname = ISNULL(LTRIM(RTRIM(o.providername)), ''),
	a.dental, 
	dentalname = ISNULL(LTRIM(RTRIM(p.providername)), ''),
	a.payorrelationship1, payorrelationshipdesc = ISNULL(t.description, ''),
	payorrelationship2
	FROM tblapplications a WITH(NOLOCK)
	OUTER APPLY (SELECT agentno, agentname, agenttype, organizationname FROM tblagents b WITH(NOLOCK) WHERE a.agentno = b.agentno) b
	OUTER APPLY (SELECT locationcode, locationname FROM tbllocations d WITH(NOLOCK) WHERE a.billingcity = d.locationcode) d
	OUTER APPLY (SELECT locationcode, locationname, locationtype FROM tbllocations e WITH(NOLOCK) WHERE a.billingprovince = e.locationcode) e
	OUTER APPLY (SELECT locationcode, locationname FROM tbllocations f WITH(NOLOCK) WHERE a.homecity = f.locationcode) f
	OUTER APPLY (SELECT locationcode, locationname, locationtype FROM tbllocations g WITH(NOLOCK) WHERE a.homeprovince = g.locationcode) g
	OUTER APPLY (SELECT productcode, productlinecode, productline FROM tblproductlines j WITH(NOLOCK) WHERE a.productcode = j.productcode) j
	OUTER APPLY (SELECT membertype, description FROM tblmembertypes k WITH(NOLOCK) WHERE a.membercategory = k.membertype) k
	OUTER APPLY (SELECT TOP 1 description, amount, tablename FROM tblgentables l WITH(NOLOCK) WHERE a.bmicategory = l.amount AND l.tablename = 'BMI CATEGORY') l
	OUTER APPLY (SELECT sacode, description, categcode FROM tblbenefitsa m WITH(NOLOCK) WHERE a.sacode = m.sacode) m
	OUTER APPLY (SELECT locationcode, locationname, locationtype FROM tbllocations n WITH(NOLOCK) WHERE a.branch = n.locationcode AND n.locationtype = 'BRANCH') n
	OUTER APPLY (SELECT providercode, providername FROM tblproviders o WITH(NOLOCK) WHERE a.provideraccess = o.providercode) o
	OUTER APPLY (SELECT providercode, providername FROM tblproviders p WITH(NOLOCK) WHERE a.dental = p.providercode) p
	OUTER APPLY (SELECT detno, contractcode, compcode, premiumclasscode, premiumclassname FROM tblcompanyclassesbilling q WITH(NOLOCK) WHERE q.compcode= 0 AND q.contractcode = 0 AND a.premiumclass = q.premiumclasscode) q
	OUTER APPLY (SELECT compcode, classcode, classname FROM tblcompanyclasses r WITH(NOLOCK) WHERE r.compcode= 0 AND r.contractcode = 0 AND a.benefitclass = r.classcode) r
	OUTER APPLY (SELECT recordno, description, tablename FROM tblgentables s WITH(NOLOCK) WHERE a.civilstatus = s.recordno AND s.tablename = 'CIVILSTATUS') AS s
	OUTER APPLY (SELECT description FROM tblgentables t WITH(NOLOCK) WHERE a.payorrelationship1 = t.recordno AND t.tablename = 'PAYOR RELATIONSHIP') t
	WHERE a.applicationcode = @lapplicationcode
	OPTION(RECOMPILE)

	EXEC sp_closesymmetric
END



GO

-- ---- sp_getretailfranchisingjournals ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getretailfranchisingjournals]
	-- Add the parameters for the stored procedure here
	@franchisecode Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lfranchisecode Int = @franchisecode

	SELECT a.detno, a.franchisecode, a.required, a.encodedby, a.dateencoded,
	description = LTRIM(RTRIM(a.description)),
	encodedbyname = ISNULL(LTRIM(RTRIM(b.username)), '')
	FROM tblapplicationjournals a WITH(NOLOCK) 
	OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.encodedby = b.userno) b
	WHERE a.franchisecode = @lfranchisecode
	ORDER BY a.dateencoded DESC
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getretailfranchisingmedhistory ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getretailfranchisingmedhistory] --2788
	-- Add the parameters for the stored procedure here
	
	@franchisecode		Int,
	@membercode			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lfranchisecode	Int	= @franchisecode,
			@lmembercode	Int	= @membercode
			
	SELECT detno, franchisecode, membercode, 
	relationship = LTRIM(RTRIM(relationship)),
	medicalhistory = LTRIM(RTRIM(medicalhistory)),
	agerange1 = LTRIM(RTRIM(agerange1)),
	healthstate = LTRIM(RTRIM(healthstate)),
	agerange2 = LTRIM(RTRIM(agerange2)),
	causeofdeath  = LTRIM(RTRIM(causeofdeath))
	FROM tblapplicationmedhistory WITH(NOLOCK)
	WHERE ((@lfranchisecode = 0 AND detno <> 0) OR (@lfranchisecode <> 0 AND franchisecode = @lfranchisecode))
	AND ((@lmembercode = 0 AND detno <> 0) OR (@lmembercode <> 0 AND membercode = @lmembercode))
	ORDER BY detno
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getretailfranchisingprevillnesses ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getretailfranchisingprevillnesses] --2788
	-- Add the parameters for the stored procedure here
	
	@franchisecode	Int,
	@categcode		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lfranchisecode	Int	= @franchisecode,
			@lcategcode		Int = @categcode

	SELECT
	medicalitem = a.detno,
	description = LTRIM(RTRIM(a.description)),
	detno = ISNULL(b.detno, 0),
	franchisecode = ISNULL(b.franchisecode, 0),
	membercode = ISNULL(b.membercode, 0),
	medicalanswer = ISNULL(b.medicalanswer, 0),
	icdno = ISNULL(b.icdno, 0),
	treatmentdate = ISNULL(b.treatmentdate, 1/1/1900),
	treatmentcourse = ISNULL(LTRIM(RTRIM(b.treatmentcourse)), ''),
	surgery = ISNULL(b.surgery, 0),
	diagnosis = ISNULL(LTRIM(RTRIM(b.diagnosis)), ''),
	hospitalname = ISNULL(LTRIM(RTRIM(b.hospitalname)), ''),
	doctorname = ISNULL(LTRIM(RTRIM(b.doctorname)), '')
	FROM tblmedicaldeclaration a WITH(NOLOCK)
	OUTER APPLY (SELECT * FROM tblapplicationprevillnesses b WITH(NOLOCK) WHERE a.detno = b.medicalitem AND b.franchisecode = @lfranchisecode) b
	WHERE a.categcode = @lcategcode 
	ORDER BY description
	OPTION(RECOMPILE)

END
GO

-- ---- sp_getroposettingsv2 ----
CREATE PROCEDURE [dbo].[sp_getroposettingsv2]
	-- Add the parameters for the stored procedure here
	
	@detno		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldetno INT = @detno

	SELECT validityperiod, registrationperiod, activationdays, 
	cancellationdays, registrationused, registrationunused, agefrom, ageto
	FROM tblcompanyclasses 
	WHERE detno = @ldetno
	OPTION(RECOMPILE)


END
GO

-- ---- sp_getsaledgerv2 ----
CREATE PROCEDURE [dbo].[sp_getsaledgerv2]
	-- Add the parameters for the stored procedure here

	@description	Varchar(200),
	@sacode			Varchar(50),
	@categcode		Int,
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	DECLARE	@ldescription	Varchar(200)	= @description,
			@lsacode		Varchar(50)		= @sacode,
			@lcategcode		Int				= @categcode,
			@lpageno		Int				= @pageno,
			@lrowctr		Int				= @rowctr

	SELECT @rowcount = COUNT(1)
	FROM tblbenefitsa a WITH(NOLOCK)  
	OUTER APPLY (SELECT b.description FROM tblgentables b WITH(NOLOCK) WHERE a.categcode = b.detno) b
	OUTER APPLY (SELECT c.username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c 
	WHERE (((@ldescription = '' AND a.sacode <> 0) OR (@ldescription <> '' AND a.description LIKE '%'+@ldescription+'%'))
	AND ((@lsacode = '' AND a.sacode <> 0) OR (@lsacode <> '' AND a.benefitcode LIKE '%'+@lsacode+'%'))
	AND ((@lcategcode = 0 AND a.sacode <> 0) OR (@lcategcode <> 0 AND a.categcode = @lcategcode)))
	OPTION(RECOMPILE)

	If @pageno <= 0 or @rowctr <= 0
		BEGIN
			SELECT a.sacode, a.categcode, a.encodedby, a.dateencoded, a.display, a.required, a.rider, a.iorta,
			benefitcode = ISNULL(LTRIM(RTRIM(a.benefitcode)),''),
			description = ISNULL(LTRIM(RTRIM(a.description)),''), 
			remarks = ISNULL(LTRIM(RTRIM(a.remarks)),''),
			categname = ISNULL(LTRIM(RTRIM(b.description)), ''),
			encodedbyname = ISNULL(LTRIM(RTRIM(c.username)), '')
			FROM tblbenefitsa a WITH(NOLOCK)  
			OUTER APPLY (SELECT b.description FROM tblgentables b WITH(NOLOCK) WHERE a.categcode = b.detno) b
			OUTER APPLY (SELECT c.username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c 
			WHERE (((@ldescription = '' AND a.sacode <> 0) OR (@ldescription <> '' AND a.description LIKE '%'+@ldescription+'%'))
			AND ((@lsacode = '' AND a.sacode <> 0) OR (@lsacode <> '' AND a.benefitcode LIKE '%'+@lsacode+'%'))
			AND ((@lcategcode = 0 AND a.sacode <> 0) OR (@lcategcode <> 0 AND a.categcode = @lcategcode)))
			ORDER BY a.description				
		END
	ELSE
		BEGIN
			SELECT a.sacode, a.categcode, a.encodedby, a.dateencoded, a.display, a.required, a.rider,  a.iorta,
			benefitcode = ISNULL(LTRIM(RTRIM(a.benefitcode)),''),
			description = ISNULL(LTRIM(RTRIM(a.description)),''), 
			remarks = ISNULL(LTRIM(RTRIM(a.remarks)),''),
			categname = ISNULL(LTRIM(RTRIM(b.description)), ''),
			encodedbyname = ISNULL(LTRIM(RTRIM(c.username)), '')
			FROM tblbenefitsa a WITH(NOLOCK)  
			OUTER APPLY (SELECT b.description FROM tblgentables b WITH(NOLOCK) WHERE a.categcode = b.detno) b
			OUTER APPLY (SELECT c.username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c 
			WHERE (((@ldescription = '' AND a.sacode <> 0) OR (@ldescription <> '' AND a.description LIKE '%'+@ldescription+'%'))
			AND ((@lsacode = '' AND a.sacode <> 0) OR (@lsacode <> '' AND a.benefitcode LIKE '%'+@lsacode+'%'))
			AND ((@lcategcode = 0 AND a.sacode <> 0) OR (@lcategcode <> 0 AND a.categcode = @lcategcode)))
			ORDER BY a.description	
			OFFSET ((@lpageno - 1) * @lrowctr) ROWS
			FETCH NEXT @lrowctr ROWS ONLY
			OPTION(RECOMPILE)
		END
END



GO

-- ---- sp_getsaledgerv3 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_getsaledgerv3]
	-- Add the parameters for the stored procedure here

	@description	Varchar(200),
	@sacode			Varchar(50),
	@categcode		Int,
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT -- can be optional and will still run without providing value.

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	DECLARE	@ldescription	Varchar(200)	= @description,
			@lsacode		Varchar(50)		= @sacode,
			@lcategcode		Int				= @categcode,
			@lpageno		Int				= @pageno,
			@lrowctr		Int				= @rowctr

	SELECT @rowcount = COUNT(1)
	FROM tblbenefitsa a WITH(NOLOCK)  
	OUTER APPLY (SELECT b.description FROM tblgentables b WITH(NOLOCK) WHERE a.categcode = b.detno) b
	OUTER APPLY (SELECT c.username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c 
	WHERE (((@ldescription = '' AND a.sacode <> 0) OR (@ldescription <> '' AND a.description LIKE '%'+@ldescription+'%'))
	AND ((@lsacode = '' AND a.sacode <> 0) OR (@lsacode <> '' AND a.benefitcode LIKE '%'+@lsacode+'%'))
	AND ((@lcategcode = 0 AND a.sacode <> 0) OR (@lcategcode <> 0 AND a.categcode = @lcategcode)))
	OPTION(RECOMPILE)

	If @pageno <= 0 or @rowctr <= 0
		BEGIN
			SELECT a.sacode, a.categcode, a.encodedby, a.dateencoded, a.display, a.required, a.rider, a.iorta,
			benefitcode = ISNULL(LTRIM(RTRIM(a.benefitcode)),''),
			description = ISNULL(LTRIM(RTRIM(a.description)),''), 
			remarks = ISNULL(LTRIM(RTRIM(a.remarks)),''),
			categname = ISNULL(LTRIM(RTRIM(b.description)), ''),
			a.dentalcoverage, dentalcoveragename = CASE WHEN a.dentalcoverage = 1 THEN 'RELIANT'
														WHEN a.dentalcoverage = 2 THEN 'HPDAI'
														ELSE ''
													END,
			encodedbyname = ISNULL(LTRIM(RTRIM(c.username)), '')
			FROM tblbenefitsa a WITH(NOLOCK)  
			OUTER APPLY (SELECT b.description FROM tblgentables b WITH(NOLOCK) WHERE a.categcode = b.detno) b
			OUTER APPLY (SELECT c.username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c 
			WHERE (((@ldescription = '' AND a.sacode <> 0) OR (@ldescription <> '' AND a.description LIKE '%'+@ldescription+'%'))
			AND ((@lsacode = '' AND a.sacode <> 0) OR (@lsacode <> '' AND a.benefitcode LIKE '%'+@lsacode+'%'))
			AND ((@lcategcode = 0 AND a.sacode <> 0) OR (@lcategcode <> 0 AND a.categcode = @lcategcode)))
			ORDER BY a.description				
		END
	ELSE
		BEGIN
			SELECT a.sacode, a.categcode, a.encodedby, a.dateencoded, a.display, a.required, a.rider,  a.iorta,
			benefitcode = ISNULL(LTRIM(RTRIM(a.benefitcode)),''),
			description = ISNULL(LTRIM(RTRIM(a.description)),''), 
			remarks = ISNULL(LTRIM(RTRIM(a.remarks)),''),
			categname = ISNULL(LTRIM(RTRIM(b.description)), ''),
			a.dentalcoverage, dentalcoveragename = CASE WHEN a.dentalcoverage = 1 THEN 'RELIANT'
														WHEN a.dentalcoverage = 2 THEN 'HPDAI'
														ELSE ''
													END,
			encodedbyname = ISNULL(LTRIM(RTRIM(c.username)), '')
			FROM tblbenefitsa a WITH(NOLOCK)  
			OUTER APPLY (SELECT b.description FROM tblgentables b WITH(NOLOCK) WHERE a.categcode = b.detno) b
			OUTER APPLY (SELECT c.username FROM tblusers c WITH(NOLOCK) WHERE a.encodedby = c.userno) c 
			WHERE (((@ldescription = '' AND a.sacode <> 0) OR (@ldescription <> '' AND a.description LIKE '%'+@ldescription+'%'))
			AND ((@lsacode = '' AND a.sacode <> 0) OR (@lsacode <> '' AND a.benefitcode LIKE '%'+@lsacode+'%'))
			AND ((@lcategcode = 0 AND a.sacode <> 0) OR (@lcategcode <> 0 AND a.categcode = @lcategcode)))
			ORDER BY a.description	
			OFFSET ((@lpageno - 1) * @lrowctr) ROWS
			FETCH NEXT @lrowctr ROWS ONLY
			OPTION(RECOMPILE)
		END
END



GO

-- ---- sp_getsoamemberbreakdownv2 ----
CREATE PROCEDURE [dbo].[sp_getsoamemberbreakdownv2]
	-- Add the parameters for the stored procedure here
	
	@soacode			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lsoacode			Int				= @soacode

	EXEC sp_opensymmetric

	SELECT membercode, 
	sobamount = sobamount,
	memberno = LTRIM(RTRIM(memberno)),
	membername = LTRIM(RTRIM(dbo.Decrypt(a.membername))),
	description = ISNULL(d.description, ''),
	categname = ISNULL(LTRIM(RTRIM(c.description)), '')
	FROM tblsoapremiummembers a WITH(NOLOCK)
	OUTER APPLY (SELECT mdflog FROM tblmembers b WITH(NOLOCK) WHERE a.membercode = b.membercode) b
	OUTER APPLY (SELECT feecode, categcode, description FROM tblfees c WITH(NOLOCK) WHERE a.feecode = c.feecode) c
	OUTER APPLY (SELECT recordno, description, tablename FROM tblgentables d WITH(NOLOCK) WHERE c.categcode = d.recordno AND d.tablename = 'FEE CATEGORY') d
	WHERE soacode = @lsoacode
	ORDER BY c.feecode

	EXEC sp_closesymmetric
END
GO

-- ---- sp_getsrauploadloamappingsettings ----
CREATE PROCEDURE [dbo].[sp_getsrauploadloamappingsettings]
	-- Add the parameters for the stored procedure here

AS
BEGIN
	
	SELECT inbox = a.loamappinginbox, 
	archive = a.loamappingarchive, 
	uploadedby = (SELECT userno FROM tblusers WHERE usercode = 'SYSGEN'),
	uploadedbyname = (SELECT username FROM tblusers WHERE usercode = 'SYSGEN'),
	branchno = (SELECT branchno FROM tblusers WHERE usercode = 'SYSGEN'),
	reportpath = (SELECT reportpath FROM tblsettingsreport)
	FROM tblsettingsmedical a WITH(NOLOCK)
	OPTION(RECOMPILE)


END
GO

-- ---- sp_getusermoduleaccessv2 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_getusermoduleaccessv2]
	-- Add the parameters for the stored procedure here
	
	@dateaccessfrom	Smalldatetime,
	@dateaccessto	Smalldatetime,
	@username		Varchar(20),
	@modulename		Varchar(200),
	@pageno			Int,
	@rowctr			Int,
	@rowcount		Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@ldateaccessfrom	Smalldatetime	= @dateaccessfrom,
			@ldateaccessto		Smalldatetime	= @dateaccessto,
			@lusername			Varchar(20)		= @username,
			@lmodulename		Varchar(200)	= @modulename,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr

	SELECT @rowcount = COUNT(1)
	FROM tblusermoduleaccess a
	OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.userno = b.userno) b
	WHERE ((YEAR(@ldateaccessfrom) = 1900 AND a.detno <> 0) OR (YEAR(@ldateaccessfrom) <> 1900 AND (CAST(a.dateaccess AS DATE) >= @ldateaccessfrom AND CAST(a.dateaccess AS DATE) <= @ldateaccessto)))
	AND ((@lusername = '' AND a.detno <> 0) OR (@lusername <> '' AND LTRIM(RTRIM(b.username)) LIKE '%'+@lusername+'%'))
	AND ((@lmodulename = '' AND a.detno <> 0) OR (@lmodulename <> '' AND a.modulename LIKE '%'+@lmodulename+'%'))
	OPTION(RECOMPILE)

	IF @pageno <= 0 OR @rowctr <= 0
		SELECT * FROM
		(
			SELECT a.detno, a.dateaccess, a.userno, a.accesscount,
			modulename = LTRIM(RTRIM(a.modulename)), 
			username = ISNULL(LTRIM(RTRIM(b.username)), '')
			FROM tblusermoduleaccess a
			OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.userno = b.userno) b
			WHERE ((YEAR(@ldateaccessfrom) = 1900 AND a.detno <> 0) OR (YEAR(@ldateaccessfrom) <> 1900 AND (CAST(a.dateaccess AS DATE) >= @ldateaccessfrom AND CAST(a.dateaccess AS DATE) <= @ldateaccessto)))
			AND ((@lusername = '' AND a.detno <> 0) OR (@lusername <> '' AND LTRIM(RTRIM(b.username)) LIKE '%'+@lusername+'%'))
			AND ((@lmodulename = '' AND a.detno <> 0) OR (@lmodulename <> '' AND a.modulename LIKE '%'+@lmodulename+'%'))
		) result
		ORDER BY dateaccess DESC
	ELSE
		SELECT * FROM
		(
			SELECT a.detno, a.dateaccess, a.userno, a.accesscount,
			modulename = LTRIM(RTRIM(a.modulename)), 
			username = ISNULL(LTRIM(RTRIM(b.username)), '')
			FROM tblusermoduleaccess a
			OUTER APPLY (SELECT username FROM tblusers b WITH(NOLOCK) WHERE a.userno = b.userno) b
			WHERE ((YEAR(@ldateaccessfrom) = 1900 AND a.detno <> 0) OR (YEAR(@ldateaccessfrom) <> 1900 AND (CAST(a.dateaccess AS DATE) >= @ldateaccessfrom AND CAST(a.dateaccess AS DATE) <= @ldateaccessto)))
			AND ((@lusername = '' AND a.detno <> 0) OR (@lusername <> '' AND LTRIM(RTRIM(b.username)) LIKE '%'+@lusername+'%'))
			AND ((@lmodulename = '' AND a.detno <> 0) OR (@lmodulename <> '' AND a.modulename LIKE '%'+@lmodulename+'%'))
		) result
		ORDER BY dateaccess DESC
		OFFSET ((@lpageno - 1) * @lrowctr) ROWS
		FETCH NEXT @lrowctr ROWS ONLY
		OPTION(RECOMPILE)
END
GO

-- ---- sp_memattachmentsoamemberdetailsv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_memattachmentsoamemberdetailsv2]
	-- Add the parameters for the stored procedure here
	@compcode		Int,
	@contractcode	Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lcompcode			Int				= @compcode,
			@lcontractcode		Int				= @contractcode

	CREATE TABLE #temp_memberamendment
	(
		membercode Int,
		amendmenttype Tinyint,
		newvalue Varchar(100),
		oldvalue Varchar(100),
		effectivity Smalldatetime,
		dateencoded Smalldatetime
	)

	INSERT INTO #temp_memberamendment
	SELECT membercode, amendmenttype, newvalue, oldvalue, effectivity, dateencoded
	FROM tblmemberamendment WITH(NOLOCK)
	WHERE compcode = @lcompcode
	AND contractcode = @lcontractcode
	AND amendmenttype IN (48, 49)
	AND statuscode = 2

    /****** Script for SelectTopNRows command from SSMS  ******/
	SELECT a.membercode, a.memberno, a.membername,
	premiumclass = ISNULL(LTRIM(RTRIM(g.oldvalue)), a.premiumclass),
	premiumclassname = ISNULL(LTRIM(RTRIM(m.premiumclassname)), ''), 
	benefitclass = ISNULL(LTRIM(RTRIM(h.newvalue)), a.benefitclass),
	a.classorder, a.streetaddress,
	policydivision = CASE WHEN ISNULL(b.diffmemberattachment, a.policydivision) = 0 THEN 0 ELSE a.policydivision END,
	a.membercategory, effectivity = ISNULL(g.effectivity, a.effectivity), a.expiry, a.origeffectivity,
	CASE WHEN ISNULL(b.diffmemberattachment, a.policydivision) = 0 AND ISNULL(b.sendbilling, a.policydivision) = 0 THEN '' ELSE ISNULL(b.shortname, '') END AS divisioncode, 
	CASE WHEN ISNULL(b.diffmemberattachment, a.policydivision) = 0 AND ISNULL(b.sendbilling, a.policydivision) = 0 THEN '' ELSE ISNULL(b.divisionname, '') END AS branchname, 
	ISNULL(c.membername, '') AS principalname, 
	ISNULL(e.description, '') AS membertype, 
	ISNULL(RTRIM(d.accountcode)+CASE WHEN a.classorder = 0 THEN RIGHT('000000'+CAST(a.membercode AS VARCHAR),6)
									 WHEN a.classorder = 1 AND a.principalcode <> 0 THEN RIGHT('000000'+CAST(a.principalcode AS VARCHAR),6)
									 ELSE RIGHT('000000'+CAST(a.membercode AS VARCHAR),6) END, '') AS account, 
	ISNULL(b.diffmemberattachment, 0) AS diffmemberattachment, 
	ISNULL(f.recordcode, '') AS companytypecode,
	a.principalcode,
	birthdate = ISNULL(a.birthdate,'1/1/1900'),
	gender = ISNULL(a.gender,''),
	civilstatus = ISNULL(a.civilstatus, 0),
	civilstatusname = ISNULL(LTRIM(RTRIM(k.description)), ''),
	datehired = ISNULL(i.datehired, '1/1/1900'),
	emailaddress = LTRIM(RTRIM(ISNULL(CONVERT(VARCHAR(100), DECRYPTBYKEY(i.emailaddress)), ''))),
	mobile =LTRIM(RTRIM(ISNULL(CONVERT(VARCHAR(100), DECRYPTBYKEY(i.mobile)), ''))),
	sssno = ISNULL(i.sssno, ''),
	tin = ISNULL(i.tin, ''),
	dependentcoveragetype = ISNULL(i.dependentcoveragetype, 0),
	dependentcoveragetypecode = ISNULL(j.recordcode, ''),
	dependentcoveragetypedesc = ISNULL(j.description, ''),
	vip = ISNULL(i.vip, 0),
	telephone = ISNULL(i.telephone, ''), --home phone
	officephone = ISNULL(i.officephone, ''),
	subgroup = ISNULL(LTRIM(RTRIM(b.divisionname)),''),
	occupation = ISNULL(LTRIM(RTRIM(i.occupation)), '') --position

	FROM tblmembers a WITH(NOLOCK)
	OUTER APPLY (SELECT membercode, principalcode, membername FROM tblmembers c WITH(NOLOCK) WHERE a.principalcode = c.membercode) c
	OUTER APPLY (SELECT compcode, shortname, divisioncode, divisionname, diffmemberattachment, sendbilling FROM tblcompanydivision b WITH(NOLOCK) WHERE a.policydivision = b.divisioncode) b
	OUTER APPLY (SELECT compcode, accountcode, companytype FROM tblcompany d WITH(NOLOCK) WHERE d.compcode = a.compcode) d
	OUTER APPLY (SELECT membertype, description FROM tblmembertypes e WITH(NOLOCK) WHERE a.membercategory = e.membertype) e
	OUTER APPLY (SELECT recordcode, recordno, detno, tablename FROM tblgentables f WITH(NOLOCK) WHERE d.companytype = f.detno AND f.tablename = 'COMPANY TYPE') f
	OUTER APPLY (SELECT TOP 1 oldvalue, effectivity FROM #temp_memberamendment g WITH(NOLOCK) WHERE a.membercode = g.membercode AND g.amendmenttype = 49 ORDER BY effectivity DESC, dateencoded DESC) g
	OUTER APPLY (SELECT TOP 1 newvalue FROM #temp_memberamendment h WITH(NOLOCK) WHERE a.membercode = h.membercode AND h.amendmenttype = 48 ORDER BY effectivity DESC, dateencoded DESC) h
	OUTER APPLY (SELECT datehired, emailaddress, mobile, sssno, tin, dependentcoveragetype, vip, telephone, officephone, occupation FROM tblmemberdetails i WITH(NOLOCK) WHERE a.membercode = i.membercode) i
	OUTER APPLY (SELECT recordno, recordcode, description, tablename FROM tblgentables j WITH(NOLOCK) WHERE i.dependentcoveragetype = j.recordno AND j.tablename = 'DEPENDENT COVERAGE TYPE') AS j
	OUTER APPLY (SELECT recordno, description, tablename FROM tblgentables k WITH(NOLOCK) WHERE a.civilstatus = k.recordno AND k.tablename = 'CIVILSTATUS') AS k
	OUTER APPLY (SELECT contractcode, compcode FROM tblcompanycontractyears l WITH(NOLOCK) WHERE a.compcode = l.compcode AND a.effectivity >= l.effectivity AND a.expiry <= l.expiry) l
	OUTER APPLY (SELECT detno, contractcode, compcode, premiumclasscode, premiumclassname FROM tblcompanyclassesbilling m WITH(NOLOCK) WHERE ((a.compcode <> 0 AND l.compcode = m.compcode AND l.contractcode = m.contractcode) OR (a.compcode = 0 AND m.compcode = 0 AND m.contractcode = 0)) AND a.premiumclass = m.premiumclasscode) m
	WHERE a.compcode = @lcompcode
	OPTION(RECOMPILE)

	DROP TABLE #temp_memberamendment
END
GO

-- ---- sp_recreatebenefitclass ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_recreatebenefitclass]
	@compcode INT,
	@contractcodeold INT,
	@contractcodenew INT,
	@encodedby INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE 
	    @lcompcode          INT = @compcode,
	    @lcontractcodeold   INT = @contractcodeold,
	    @lcontractcodenew   INT = @contractcodenew,
	    @lencodedby         INT = @encodedby

    INSERT INTO tblcompanyclasses (
        compcode, contractcode, encodedby, agefrom, ageto, agefromdep, agetodep,
        classdetno, classcode, classname, products, cardhospital, cardcoordinator,
        cardclinic, cardmaternity, cardmaxbenefit, cardped, cardlifetime, carddental,
        cardagelimit, cardroomlimit, cardroomlimitno, cardhospitalno, cardcoordinatorno,
        cardclinicno, cardmaternityno, carddentalno, cardcoverageinc, cardcoverageadd, 
        cardavailmentinc, cardavailmentadd, cardmodeinc, cardmodeadd, cardexpectedinc, cardexpectedadd,
        effectivity, expiry, parentcompcode, productcode, renewalclass, templatetype,
        validityperiod, registrationperiod, activationdays, registrationused, registrationunused,
        ilbundled, classdesc, importedcode, withuploadsob, displaysalesportal, dateencoded,
        cancellationdays, topupplan, coveragetype, grandfatheredplan, dentalinformation, vpdlinkcode
    )  
    SELECT 
        a.compcode, @lcontractcodenew, @lencodedby, a.agefrom, a.ageto, a.agefromdep, a.agetodep,
        a.classdetno, a.classcode, a.classname, a.products, a.cardhospital, a.cardcoordinator,
        a.cardclinic, a.cardmaternity, a.cardmaxbenefit, a.cardped, a.cardlifetime, a.carddental,
        a.cardagelimit, a.cardroomlimit, a.cardroomlimitno, a.cardhospitalno, a.cardcoordinatorno,
        a.cardclinicno, a.cardmaternityno, a.carddentalno, a.cardcoverageinc, a.cardcoverageadd, 
        a.cardavailmentinc, a.cardavailmentadd, a.cardmodeinc, a.cardmodeadd, a.cardexpectedinc, a.cardexpectedadd,
        ISNULL(c.effectivity, '1900-01-01'), ISNULL(c.expiry, '1900-01-01'), a.parentcompcode, a.productcode, a.renewalclass, a.templatetype,
        a.validityperiod, a.registrationperiod, a.activationdays, a.registrationused, a.registrationunused,
        a.ilbundled, a.classdesc, a.importedcode, a.withuploadsob, a.displaysalesportal, GETDATE(),
        a.cancellationdays, a.topupplan, a.coveragetype, a.grandfatheredplan, a.dentalinformation, a.vpdlinkcode
    FROM tblcompanyclasses a WITH(NOLOCK) 
    OUTER APPLY (SELECT classcode, classname FROM tblcompanyclasses b WITH(NOLOCK) 
        WHERE b.compcode = @lcompcode
        AND b.contractcode   = @lcontractcodenew
        AND b.classcode = a.classcode
        AND b.classname = a.classname
    ) AS b
    OUTER APPLY (SELECT effectivity, expiry FROM tblcompanycontractyears c WITH(NOLOCK) 
        WHERE c.contractcode = @lcontractcodenew
    ) AS c
    WHERE a.compcode = @lcompcode
        AND a.contractcode = @lcontractcodeold
        AND b.classcode IS NULL 

    SELECT @lcompcode AS compcode, @lcontractcodeold AS contractcodeold, @lcontractcodenew AS contractcodenew, @@ROWCOUNT AS inserttotal

END
GO

-- ---- sp_recreatebenefiticdlimit ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_recreatebenefiticdlimit]
	@compcode INT,
	@contractcodeold INT,
	@contractcodenew INT,
	@encodedby INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE 
	    @lcompcode          INT = @compcode,
	    @lcontractcodeold   INT = @contractcodeold,
	    @lcontractcodenew   INT = @contractcodenew,
	    @lencodedby         INT = @encodedby

        INSERT INTO tblcompanybenefiticdlimit (
            compcode, plancode, icdno, classification, limitamount, limitamountspillover,
            remarks, ped, catastrophic, restricted, basicascharged, majorascharged, membertype,
            membertypemajor, membertypespillover, categcode, claimserviceindex, claimserviceitems,
            packagegroup, coinsurance, coinsurancespillover, coinsurancelimit, limitfrequency,
            congenital, benefitcategory, display, withmemo, benefitmemo, reimbursementclaim, copayment, 
            nonaccredited, encodedby, dateencoded, amount, limitmajor, limitsecondlevel, claimservices,	
            coveredmonth, olddetno, limitamountre, limitamountnan, restrictedre, restrictednan, limitfrequencyre, 
            limitfrequencynan, restrictedmonths, coveredmonths, retaildetno, rowmarker, limitamountmajor, 
            limitfrequencymajor, coinsurancemajor, coinsurancemajor2, importedcode, amountrate, limitamountrerate,
            limitamountnanrate, limitamountmajorrate, oldplancode, usemajormed
        )
        SELECT 
            @lcompcode, b.plancode, a.icdno, a.classification, a.limitamount, a.limitamountspillover,
            a.remarks, a.ped, a.catastrophic, a.restricted, a.basicascharged, a.majorascharged, a.membertype,
            a.membertypemajor, a.membertypespillover, a.categcode, a.claimserviceindex, a.claimserviceitems,
            a.packagegroup, a.coinsurance, a.coinsurancespillover, a.coinsurancelimit, a.limitfrequency,
            a.congenital, a.benefitcategory, a.display, a.withmemo, a.benefitmemo, a.reimbursementclaim, a.copayment, 
            a.nonaccredited, @Lencodedby, GETDATE(), a.amount, a.limitmajor, a.limitsecondlevel, a.claimservices,
            a.coveredmonth, a.detno, a.limitamountre, a.limitamountnan, a.restrictedre, a.restrictednan, a.limitfrequencyre, 
            a.limitfrequencynan, a.restrictedmonths, a.coveredmonths, a.retaildetno, a.rowmarker, a.limitamountmajor, 
            a.limitfrequencymajor, a.coinsurancemajor, a.coinsurancemajor2, a.importedcode, a.amountrate, a.limitamountrerate,
            a.limitamountnanrate, a.limitamountmajorrate, a.plancode, a.usemajormed
        FROM tblcompanybenefiticdlimit a
        OUTER APPLY (
            SELECT b.plancode
            FROM tblcompanybenefitplan b WITH(NOLOCK)
            WHERE b.oldplancode  = a.plancode
                AND b.compcode     = @lcompcode
                AND b.contractcode = @lcontractcodenew
        ) AS b
        OUTER APPLY (
            SELECT detno
            FROM tblcompanybenefiticdlimit c WITH(NOLOCK)
            WHERE c.compcode            = @lcompcode
                AND c.plancode          = b.plancode
                AND c.icdno             = a.icdno
                AND c.claimserviceitems = a.claimserviceitems
                AND c.membertype        = a.membertype
        ) AS c
        WHERE b.plancode IS NOT NULL
            AND c.detno  IS NULL

    SELECT @lcompcode AS compcode, @lcontractcodeold AS contractcodeold, @lcontractcodenew AS contractcodenew, @@ROWCOUNT AS inserttotal

END
GO

-- ---- sp_recreatebenefitlimits ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_recreatebenefitlimits]
	@compcode INT,
	@contractcodeold INT,
	@contractcodenew INT,
	@encodedby INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statementa.
	SET NOCOUNT ON;

    DECLARE 
	    @lcompcode          INT = @compcode,
	    @lcontractcodeold   INT = @contractcodeold,
	    @lcontractcodenew   INT = @contractcodenew,
	    @lencodedby         INT = @encodedby


    INSERT INTO tblcompanybenefitlimits (
        compcode, contractcode, plancode, cptno, sacode, limitamount, limitamountmajor, limitamountspillover, 
        basicfsrate, majorfsrate, spilloverfsrate, limitfrequency, basicascharged, majorascharged, roomlimit,
        membertype, membertypemajor, membertypespillover, remarks, excluded, limittype,
        groupcode, migrated, withmemo, coinsurance, coinsurancemajor, coinsurancespillover, coinsurancelimit,
        claimserviceindex, claimserviceitems, formulatedschemerate, reimbursementclaim, copayment, 
        nonaccredited, encodedby, dateencoded, olddetno, oldplancode, limitmajor, limitsecondlevel, wfs, 
        peraccount, perclaim, coveredmonth, claimservices, pericd, usemajormed, customplancode, packagelimit, 
        limitamountre, limitmajorre, dpt, packagerestrict, packagegroup, sharedmajorlimit, sharedlimit, 
        limitamountnan, excludedre, excludednan, limitfrequencyre, limitfrequencynan, amdtcode, percontractyear, 
        peritemcoin, excludererate, franchisedetno, retaildetno, benefitcategory, delcode, display, rowmarker,
        limitfrequencymajor, coinsurancemajor2, importedcode, amountrate, limitamountrerate, limitamountnanrate,	
        limitamountmajorrate, restrictedmonths, coveredmonths, formulatedschememajor, multiplier
    )
    SELECT 
        @lcompcode, @lcontractcodenew, b.plancode, a.cptno, a.sacode, a.limitamount, a.limitamountmajor, a.limitamountspillover, 
        a.basicfsrate, a.majorfsrate, a.spilloverfsrate, a.limitfrequency, a.basicascharged, a.majorascharged, a.roomlimit,
        a.membertype, a.membertypemajor, a.membertypespillover, a.remarks, a.excluded, a.limittype,
        a.groupcode, a.migrated, a.withmemo, a.coinsurance, a.coinsurancemajor, a.coinsurancespillover, a.coinsurancelimit,
        a.claimserviceindex, a.claimserviceitems, a.formulatedschemerate, a.reimbursementclaim, a.copayment, 
        a.nonaccredited, @lencodedby, GETDATE(), a.detno, a.plancode, limitmajor, limitsecondlevel, wfs, 
        a.peraccount, a.perclaim, a.coveredmonth, a.claimservices, a.pericd, a.usemajormed, a.customplancode, a.packagelimit, 
        a.limitamountre, a.limitmajorre, a.dpt, a.packagerestrict, a.packagegroup, a.sharedmajorlimit, a.sharedlimit, 
        a.limitamountnan, a.excludedre, a.excludednan, a.limitfrequencyre, a.limitfrequencynan, a.amdtcode, a.percontractyear, 
        a.peritemcoin, a.excludererate, a.franchisedetno, a.retaildetno, a.benefitcategory, a.delcode, a.display, a.rowmarker,
        a.limitfrequencymajor, a.coinsurancemajor2, a.importedcode, a.amountrate, a.limitamountrerate, a.limitamountnanrate,	
        a.limitamountmajorrate, a.restrictedmonths, a.coveredmonths, a.formulatedschememajor, a.multiplier
    FROM tblcompanybenefitlimits a
    OUTER APPLY (
        SELECT b.plancode
        FROM tblcompanybenefitplan b WITH(NOLOCK)
        WHERE b.oldplancode  = a.plancode
            AND b.compcode     = @lcompcode
            AND b.contractcode = @lcontractcodenew
    ) AS b
    OUTER APPLY (
        SELECT detno
        FROM tblcompanybenefitlimits c WITH(NOLOCK)
        WHERE c.compcode            = @lcompcode
            AND c.contractcode      = @lcontractcodenew
            AND c.plancode          = b.plancode
            AND c.cptno             = a.cptno
            AND c.sacode            = a.sacode
            AND c.claimserviceitems = a.claimserviceitems
            AND c.membertype        = a.membertype
    ) AS c
    WHERE b.plancode  IS NOT NULL
        AND c.detno IS NULL

    SELECT @lcompcode AS compcode, @lcontractcodeold AS contractcodeold, @lcontractcodenew AS contractcodenew, @@ROWCOUNT AS inserttotal

END
GO

-- ---- sp_recreatebenefitplan ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_recreatebenefitplan]
	-- Add the parameters for the stored procedure here
	@compcode INT,
	@contractcodeold INT,
	@contractcodenew INT,
	@encodedby INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE 
	    @lcompcode          INT = @compcode,
	    @lcontractcodeold   INT = @contractcodeold,
	    @lcontractcodenew   INT = @contractcodenew,
	    @lencodedby         INT = @encodedby

    INSERT INTO tblcompanybenefitplan (
        compcode, contractcode, planname, membertype, membertypemajor, provideraccess,
        sobplancode, sobmajorcode, limitamount, limitamountac, limitamountmajor,	
        limitamountspillover, classification, claimservices, claimserviceitems,	
        philhealth, remarks, coinsurance, coinsurancemajor, coinsurancespillover, 
        deductible, deductiblemajor, deductiblespillover, deductiblere, deductiblemajorre,
        deductiblespilloverre, interperiodprin, interperioddep, interperiodddprin, 
        interperioddddep, billingschedule, applicablegender, preparedby, prepareddate,
        rowmarker, usemajormed,
        membertypespillover, limitamountmajorac, sharedmajorlimit, sharedspillover,
        effectivity, expiry, reimbursementrate, productcode, oldplancode, migrated,
        retail, retailplancode, vattype, groupcode, plandesc, coinsurancelimit,
        renewalplancode, programtype, pecwaived, selectiontype, validityperiod, 
        registrationperiod, activationdays, registrationused, registrationunused, sumassured,	
        agefrom, ageto, plantype, withsobimage, displaysalesportal, ilbundled, adminfee, 
        amdtcode, archive, benefitclassdetno, brokerfee, callless, classcode, clbufferlimit,	
        coininnerlimit, coinsurancemajorre, coinsurancere, coinsurancespilloverre, computeinner, 
        customplancode, excessguarantee, hibamount, mobile, prorated, sharedlimit, privilegecare, 
        benefittype, importedcode, limitsetup, limitsetupothers
    )
    SELECT 
        @lcompcode, @Lcontractcodenew, a.planname, a.membertype, a.membertypemajor, a.provideraccess,
        a.sobplancode, a.sobmajorcode, a.limitamount, a.limitamountac, a.limitamountmajor,	
        a.limitamountspillover, a.classification, a.claimservices, a.claimserviceitems,	
        a.philhealth, a.remarks, a.coinsurance, a.coinsurancemajor, a.coinsurancespillover, 
        a.deductible, a.deductiblemajor, a.deductiblespillover, a.deductiblere, a.deductiblemajorre,
        a.deductiblespilloverre, a.interperiodprin, a.interperioddep, a.interperiodddprin, 
        a.interperioddddep, a.billingschedule, a.applicablegender, @lencodedby, GETDATE(),
        a.rowmarker, a.usemajormed,
        a.membertypespillover, a.limitamountmajorac, a.sharedmajorlimit, a.sharedspillover,
        ISNULL(d.effectivity, '1900-01-01'), ISNULL(d.expiry, '1900-01-01'), a.reimbursementrate, a.productcode, a.plancode, a.migrated,
        a.retail, a.retailplancode, a.vattype, a.groupcode, a.plandesc, a.coinsurancelimit,
        a.renewalplancode, a.programtype, a.pecwaived, a.selectiontype, a.validityperiod, 
        a.registrationperiod, a.activationdays, a.registrationused, a.registrationunused, a.sumassured,	
        a.agefrom, a.ageto, a.plantype, a.withsobimage, a.displaysalesportal, a.ilbundled, a.adminfee, 
        a.amdtcode, a.archive, a.benefitclassdetno, a.brokerfee, a.callless, a.classcode, a.clbufferlimit,	
        a.coininnerlimit, a.coinsurancemajorre, a.coinsurancere, a.coinsurancespilloverre, a.computeinner, 
        a.customplancode, a.excessguarantee, a.hibamount, a.mobile, a.prorated, a.sharedlimit, a.privilegecare, 
        a.benefittype, a.importedcode, a.limitsetup, a.limitsetupothers
    FROM tblcompanybenefitplan a WITH(NOLOCK)
    OUTER APPLY (SELECT classcode FROM tblcompanyclasses b WITH(NOLOCK) 
        WHERE b.compcode     = @Lcompcode
        AND b.contractcode   = @Lcontractcodenew
        AND b.classcode      = a.classcode
    ) AS b
    OUTER APPLY (SELECT plancode FROM tblcompanybenefitplan c WITH(NOLOCK) 
        WHERE c.compcode        = @Lcompcode
        AND c.contractcode      = @Lcontractcodenew
        AND c.classcode         = a.classcode
        AND c.sobplancode       = a.sobplancode
        AND c.claimserviceitems = a.claimserviceitems
    ) AS c
    OUTER APPLY (SELECT effectivity, expiry FROM tblcompanycontractyears d WITH(NOLOCK) 
        WHERE d.contractcode    = @lcontractcodenew
    ) AS d
    WHERE a.compcode       = @Lcompcode
        AND a.contractcode = @Lcontractcodeold
        AND b.classcode     IS NOT NULL 
        AND c.plancode      IS NULL

    SELECT @lcompcode AS compcode, @lcontractcodeold AS contractcodeold, @lcontractcodenew AS contractcodenew, @@ROWCOUNT AS inserttotal

END
GO

-- ---- sp_recreatebenefitproviders ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_recreatebenefitproviders]
	@compcode INT,
	@contractcodeold INT,
	@contractcodenew INT,
	@encodedby INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE 
	    @lcompcode          INT = @compcode,
	    @lcontractcodeold   INT = @contractcodeold,
	    @lcontractcodenew   INT = @contractcodenew,
	    @lencodedby         INT = @encodedby

    INSERT INTO tblcompanybenefitproviders (
        plancode, compcode, providercode, regioncode, regionno, 
        allowaccess, remarks, effectivity, encodedby, dateencoded,
        claimserviceindex, claimserviceitems, templateno, importedcode,
        oldplancode, olddetno

    )
    SELECT 
        b.plancode, @Lcompcode, a.providercode, a.regioncode, a.regionno, 
        a.allowaccess, a.remarks, ISNULL(d.effectivity, '1900-01-01'), @Lencodedby, GETDATE(),
        a.claimserviceindex, a.claimserviceitems, a.templateno, a.importedcode,
        a.plancode, a.detno
    FROM tblcompanybenefitproviders a
    OUTER APPLY (
        SELECT b.plancode
        FROM tblcompanybenefitplan b WITH(NOLOCK)
        WHERE b.oldplancode  = a.plancode
            AND b.compcode     = @Lcompcode
            AND b.contractcode = @lcontractcodenew
    ) AS b
    OUTER APPLY (
        SELECT detno
        FROM tblcompanybenefitproviders c WITH(NOLOCK)
        WHERE c.compcode       = @Lcompcode
            AND c.plancode     = b.plancode
            AND c.providercode = a.providercode
            AND c.regioncode   = a.regioncode
    ) AS c
    OUTER APPLY (
        SELECT effectivity FROM tblcompanycontractyears d WITH(NOLOCK) 
        WHERE d.contractcode    = @lcontractcodenew
    ) AS d
    WHERE b.plancode  IS NOT NULL
        AND c.detno IS NULL


    SELECT @lcompcode AS compcode, @lcontractcodeold AS contractcodeold, @lcontractcodenew AS contractcodenew, @@ROWCOUNT AS inserttotal


END
GO

-- ---- sp_recreatecompanypremiummember ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_recreatecompanypremiummember]
	@compcode INT,
	@contractcodeold INT,
	@contractcodenew INT,
	@encodedby INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE 
	    @lcompcode          INT = @compcode,
	    @lcontractcodeold   INT = @contractcodeold,
	    @lcontractcodenew   INT = @contractcodenew,
	    @lencodedby         INT = @encodedby

	INSERT INTO tblcompanypremiummember (
        compcode, contractcode, encodedby, premiumcode,
        membertype, agefrom, ageto, premiumrate, rowmarker, dateencoded
    )  
    SELECT 
        @lcompcode, @lcontractcodenew, @lencodedby, ISNULL(b.premiumcode, 0),
        a.membertype, a.agefrom, a.ageto, a.premiumrate, a.rowmarker, GETDATE()
    FROM tblcompanypremiummember a WITH(NOLOCK) 
    OUTER APPLY (SELECT premiumcode FROM tblcompanypremiums b WITH(NOLOCK) 
        WHERE b.compcode = @lcompcode
            AND b.contractcode   = @lcontractcodenew
            AND b.oldbenefitfeedetno = a.premiumcode
    ) AS b
    OUTER APPLY (SELECT premiumcode  FROM tblcompanypremiummember c WITH(NOLOCK) 
        WHERE c.compcode        = @lcompcode
            AND c.contractcode  = @lcontractcodenew
            AND c.premiumcode = ISNULL(b.premiumcode, 0)
            AND c.membertype   = a.membertype
            AND c.agefrom   = a.agefrom
            AND c.ageto = a.ageto
            AND c.premiumrate = a.premiumrate
    ) AS c
    WHERE a.compcode = @lcompcode
        AND a.contractcode = @lcontractcodeold
        AND c.premiumcode  IS NULL

    SELECT @lcompcode AS compcode, @lcontractcodeold AS contractcodeold, @lcontractcodenew AS contractcodenew, @@ROWCOUNT AS inserttotal

END
GO

-- ---- sp_recreatecompanypremiums ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_recreatecompanypremiums]
	@compcode INT,
	@contractcodeold INT,
	@contractcodenew INT,
	@encodedby INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE 
	    @lcompcode          INT = @compcode,
	    @lcontractcodeold   INT = @contractcodeold,
	    @lcontractcodenew   INT = @contractcodenew,
	    @lencodedby         INT = @encodedby
    
    INSERT INTO tblcompanypremiums (
        compcode, contractcode, encodedby, oldbenefitfeedetno, billclassdetno,
        feecode, sumassured, perbilling, allowprorated, dateencoded, 
        effectivity, expiry, extensioncode
    )  
    SELECT 
        @lcompcode, @lcontractcodenew, @lencodedby, a.premiumcode, ISNULL(b.detno, 0),
        a.feecode, a.sumassured, a.perbilling, a.allowprorated, GETDATE(), 
        ISNULL(d.effectivity, '1900-01-01'), ISNULL(d.expiry, '1900-01-01'), a.extensioncode
    FROM tblcompanypremiums a WITH(NOLOCK) 
    OUTER APPLY (SELECT detno FROM tblcompanyclassesbilling b WITH(NOLOCK) 
        WHERE b.compcode = @lcompcode
            AND b.contractcode   = @lcontractcodenew
            AND b.oldplancode = a.billclassdetno
    ) AS b
    OUTER APPLY (SELECT premiumcode  FROM tblcompanypremiums c WITH(NOLOCK) 
        WHERE c.compcode        = @lcompcode
            AND c.contractcode  = @lcontractcodenew
            AND c.billclassdetno = ISNULL(b.detno, 0)
            AND c.feecode        = a.feecode
    ) AS c
    OUTER APPLY (SELECT effectivity, expiry FROM tblcompanycontractyears d WITH(NOLOCK) 
        WHERE d.contractcode = @lcontractcodenew
    ) AS d
    WHERE a.compcode = @lcompcode
        AND a.contractcode = @lcontractcodeold
        AND c.premiumcode  IS NULL

    SELECT @lcompcode AS compcode, @lcontractcodeold AS contractcodeold, @lcontractcodenew AS contractcodenew, @@ROWCOUNT AS inserttotal

END
GO

-- ---- sp_recreatecompclassesv4 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_recreatecompclassesv4]
-- Add the parameters for the stored procedure here
	
	@olddetno			Int,
	@compcode			Int,
	@contractcode		Int,
	@classcode			Varchar(50),
	@classname			Varchar(150),
	@classdesc			Varchar(240),
	@templatetype		Int,
	@productcode		Int,
	@effectivity		Smalldatetime,		--base from contractcode or input
	@expiry				Smalldatetime,		--base from contractcode or input
	@agefrom			Numeric(3,0),
	@ageto				Numeric(3,0),
	@agefromdep			Numeric(3,0),
	@agetodep			Numeric(3,0),
	@userno				Int,
	@ilbundled			Bit,
	@topupplan			Bit,
	@coveragetype		Tinyint,
	@grandfatheredplan	Bit

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lolddetno			Int				= @olddetno,
			@lcompcode			Int				= @compcode,
			@lcontractcode		Int				= @contractcode,
			@lclasscode			Varchar(50)		= @classcode,
			@lclassname			Varchar(150)	= @classname,
			@lclassdesc			Varchar(240)	= @classdesc,
			@ltemplatetype		Int				= @templatetype,
			@lproductcode		Int				= @productcode,
			@leffectivity		Smalldatetime	= @effectivity,		--base from contractcode or input
			@lexpiry			Smalldatetime	= @expiry,			--base from contractcode or input
			@lagefrom			Numeric(3,0)	= @agefrom,
			@lageto				Numeric(3,0)	= @ageto,
			@lagefromdep		Numeric(3,0)	= @agefromdep,
			@lagetodep			Numeric(3,0)	= @agetodep,
			@luserno			Int				= @userno,
			@lilbundled			Bit				= @ilbundled,
			@ltopupplan			Bit				= @topupplan,
			@lcoveragetype		Tinyint			= @coveragetype,
			@lgrandfatheredplan	Bit				= @grandfatheredplan,
			@ldetno				Int				= 0

	INSERT INTO tblcompanyclasses(compcode, classcode, classname, classdesc, agefrom, ageto, agefromdep, agetodep, contractcode, parentcompcode, effectivity, expiry, productcode, templatetype, renewalclass, ilbundled, topupplan, encodedby, coveragetype, grandfatheredplan, dentalinformation,dateencoded)
	SELECT @lcompcode, @lclasscode, @lclassname, @lclassdesc, @lagefrom, @lageto, @lagefromdep, @lagetodep, @lcontractcode, parentcompcode, @leffectivity, @lexpiry, @lproductcode, @ltemplatetype, renewalclass, @lilbundled, @ltopupplan, @luserno, @lcoveragetype, @lgrandfatheredplan, a.dentalinformation,GETDATE()
	FROM tblcompanyclasses a 
	WHERE a.detno = @lolddetno
	SELECT @ldetno = @@IDENTITY
	OPTION(RECOMPILE)	
	
	SELECT @ldetno AS detno

END
GO

-- ---- sp_recreatecompclassesv5 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_recreatecompclassesv5]
-- Add the parameters for the stored procedure here
	
	@olddetno			Int,
	@compcode			Int,
	@contractcode		Int,
	@classcode			Varchar(50),
	@classname			Varchar(150),
	@classdesc			Varchar(240),
	@templatetype		Int,
	@productcode		Int,
	@effectivity		Smalldatetime,		--base from contractcode or input
	@expiry				Smalldatetime,		--base from contractcode or input
	@agefrom			Numeric(3,0),
	@ageto				Numeric(3,0),
	@agefromdep			Numeric(3,0),
	@agetodep			Numeric(3,0),
	@userno				Int,
	@ilbundled			Bit,
	@topupplan			Bit,
	@coveragetype		Tinyint,
	@grandfatheredplan	Bit,
	@clinicbased		Bit

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lolddetno			Int				= @olddetno,
			@lcompcode			Int				= @compcode,
			@lcontractcode		Int				= @contractcode,
			@lclasscode			Varchar(50)		= @classcode,
			@lclassname			Varchar(150)	= @classname,
			@lclassdesc			Varchar(240)	= @classdesc,
			@ltemplatetype		Int				= @templatetype,
			@lproductcode		Int				= @productcode,
			@leffectivity		Smalldatetime	= @effectivity,		--base from contractcode or input
			@lexpiry			Smalldatetime	= @expiry,			--base from contractcode or input
			@lagefrom			Numeric(3,0)	= @agefrom,
			@lageto				Numeric(3,0)	= @ageto,
			@lagefromdep		Numeric(3,0)	= @agefromdep,
			@lagetodep			Numeric(3,0)	= @agetodep,
			@luserno			Int				= @userno,
			@lilbundled			Bit				= @ilbundled,
			@ltopupplan			Bit				= @topupplan,
			@lcoveragetype		Tinyint			= @coveragetype,
			@lgrandfatheredplan	Bit				= @grandfatheredplan,
			@lclinicbased		Bit				= @clinicbased,
			@ldetno				Int				= 0

	INSERT INTO tblcompanyclasses(compcode, classcode, classname, classdesc, agefrom, ageto, agefromdep, 
	agetodep, contractcode, parentcompcode, effectivity, expiry, productcode, templatetype, renewalclass, 
	ilbundled, topupplan, encodedby, coveragetype, grandfatheredplan, dentalinformation,dateencoded, clinicbased)
	SELECT @lcompcode, @lclasscode, @lclassname, @lclassdesc, @lagefrom, @lageto, @lagefromdep, 
	@lagetodep, @lcontractcode, parentcompcode, @leffectivity, @lexpiry, @lproductcode, @ltemplatetype, renewalclass,
	@lilbundled, @ltopupplan, @luserno, @lcoveragetype, @lgrandfatheredplan, a.dentalinformation,GETDATE(), @lclinicbased
	FROM tblcompanyclasses a 
	WHERE a.detno = @lolddetno
	SELECT @ldetno = @@IDENTITY
	OPTION(RECOMPILE)	
	
	SELECT @ldetno AS detno

END
GO

-- ---- sp_recreatepremiumclass ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_recreatepremiumclass]
	@compcode INT,
	@contractcodeold INT,
	@contractcodenew INT,
	@encodedby INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE 
	    @lcompcode          INT = @compcode,
	    @lcontractcodeold   INT = @contractcodeold,
	    @lcontractcodenew   INT = @contractcodenew,
	    @lencodedby         INT = @encodedby

    INSERT INTO tblcompanyclassesbilling (
        compcode, contractcode, billingschedule, premiumclasscode, premiumclassname, 
        dateencoded, encodedby, effectivity, expiry, productcode, templatetype, 
        vattype, renewalclass, validityperiod, oldplancode, displaysalesportal, 
        premiumclassdesc, roomcategory
    )  
    SELECT 
        a.compcode, @lcontractcodenew, a.billingschedule, a.premiumclasscode, a.premiumclassname, 
        GETDATE(), @lencodedby, ISNULL(d.effectivity, '1900-01-01'), ISNULL(d.expiry, '1900-01-01'), a.productcode, a.templatetype, 
        a.vattype, a.renewalclass, a.validityperiod, a.detno, a.displaysalesportal, 
        a.premiumclassdesc, a.roomcategory
    FROM tblcompanyclassesbilling a WITH(NOLOCK) 
    OUTER APPLY (SELECT billingschedule, premiumclasscode, premiumclassname FROM tblcompanyclassesbilling b WITH(NOLOCK) 
        WHERE b.compcode = @lcompcode
        AND b.contractcode   = @lcontractcodenew
        AND b.premiumclasscode = a.premiumclasscode
        AND b.premiumclassname = a.premiumclassname
    ) AS b 
    OUTER APPLY (SELECT effectivity, expiry FROM tblcompanycontractyears d WITH(NOLOCK) 
        WHERE d.contractcode = @lcontractcodenew
    ) AS d
    WHERE a.compcode = @lcompcode
        AND a.contractcode = @lcontractcodeold
        AND b.premiumclasscode IS NULL 
    
    SELECT @lcompcode AS compcode, @lcontractcodeold AS contractcodeold, @lcontractcodenew AS contractcodenew, @@ROWCOUNT AS inserttotal

END
GO

-- ---- sp_removeprovidercontractyear ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_removeprovidercontractyear]
	@contractcode INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @lcontractcode	INT		= ISNULL(@contractcode, 0),
			@lprovidercode	INT		= 0,
			@lstatus		BIT		= 0

	SELECT TOP 1
		@lprovidercode = providercode
	FROM tblprovidercontractyears
	WHERE contractcode = @lcontractcode

	IF (@lprovidercode > 0) 
	BEGIN

		DELETE FROM tblprovidercontractyears WHERE contractcode = @contractcode

		IF ((SELECT COUNT(*) FROM tblprovidercontractyears WHERE providercode = @lprovidercode) <= 0)
		BEGIN
			UPDATE tblproviders
			SET accredited		= 0,
				dateaccredited	= '1900-01-01',
				accreditrenewal ='1900-01-01'
			WHERE providercode = @lprovidercode
		END

		SET @lstatus = 1
	END

	SELECT @lstatus AS status
END
GO

-- ---- sp_saveaccountclassbillingv3 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_saveaccountclassbillingv3]
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@compcode			Int,
	@contractcode		Int,
	@effectivity		Smalldatetime,
	@expiry				Smalldatetime,
	@billingschedule	TinyInt,
	@classcode			Varchar(50),
	@classname			Varchar(150),
	@classdesc			Varchar(150),
	@parentcompcode		Int,
	@productcode		Int,
	@templatetype		Int,
	@vattype			Int,
	@displaysalesportal	Bit,
	@encodedby			Int,
	@roomcategory		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldetno					Int				= @detno,
			@lcompcode				Int				= @compcode,
			@lcontractcode			Int				= @contractcode,
			@leffectivity			Smalldatetime	= @effectivity,
			@lexpiry				Smalldatetime	= @expiry,
			@lclasscode				Varchar(50)		= @classcode,
			@lclassname				Varchar(150)	= @classname,
			@lclassdesc				Varchar(150)	= @classdesc,
			@lbillingschedule		TinyInt			= @billingschedule,
			@lparentcompcode		Int				= @parentcompcode,
			@lproductcode			Int				= @productcode,
			@ltemplatetype			Int				= @templatetype,
			@lvattype				Int				= @vattype,
			@ldisplaysalesportal	Bit				= @displaysalesportal,
			@lencodedby				Int				= @encodedby,
			@lroomcategory			Int				= @roomcategory

    IF @ldetno = 0 OR @ldetno = NULL
		BEGIN
			INSERT INTO tblcompanyclassesbilling(compcode, parentcompcode, templatetype, encodedby, dateencoded)
			VALUES(@lcompcode, @lparentcompcode, @ltemplatetype, @lencodedby, GETDATE())
			SELECT @ldetno = @@IDENTITY
		END

	UPDATE tblcompanyclassesbilling
	SET premiumclasscode	= @lclasscode,
		premiumclassname	= @lclassname,
		premiumclassdesc	= @lclassdesc,
		contractcode		= @lcontractcode,
		effectivity			= @leffectivity,
		expiry				= @lexpiry,
		billingschedule		= @lbillingschedule,
		productcode			= @lproductcode,
		templatetype		= @ltemplatetype,
		vattype				= @lvattype,
		displaysalesportal	= @ldisplaysalesportal,
		roomcategory		= @lroomcategory
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	SELECT @ldetno AS detno

END
GO

-- ---- sp_saveaccountclassesv5 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveaccountclassesv5]
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@compcode			Int,
	@parentcompcode		Int,
	@contractcode		Int,
	@productcode		Int,
	@templatetype		Int,
	@effectivity		Smalldatetime,
	@expiry				Smalldatetime,
	@agefrom			Numeric(3,0),
	@ageto				Numeric(3,0),
	@agefromdep			Numeric(3,0),
	@agetodep			Numeric(3,0),
	@classcode			Varchar(50),
	@classname			Varchar(150),
	@classdesc			Varchar(240),
	@ilbundled			Bit,
	@topupplan			Bit,
	@coveragetype		Tinyint,
	@grandfatheredplan	Bit,
	@encodedby			Int,
	@dentalinformation	Bit

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldetno				Int				= @detno,
			@lcompcode			Int				= @compcode,
			@lparentcompcode	Int				= @parentcompcode,
			@lcontractcode		Int				= @contractcode,
			@leffectivity		Smalldatetime	= @effectivity,
			@lexpiry			Smalldatetime	= @expiry,
			@lproductcode		Int				= @productcode,
			@ltemplatetype		Int				= @templatetype,
			@lagefrom			Numeric(3,0)	= @agefrom,
			@lageto				Numeric(3,0)	= @ageto,
			@lagefromdep		Numeric(3,0)	= @agefromdep,
			@lagetodep			Numeric(3,0)	= @agetodep,
			@lclasscode			Varchar(50)		= @classcode,
			@lclassname			Varchar(150)	= @classname,
			@lclassdesc			Varchar(240)	= @classdesc,
			@lilbundled			Bit				= @ilbundled,
			@ltopupplan			Bit				= @topupplan,
			@lcoveragetype		Tinyint			= @coveragetype,
			@lgrandfatheredplan	Bit				= @grandfatheredplan,
			@lencodedby			Int				= @encodedby,
			@ldentalinformation	Bit				= @dentalinformation,
			@loldclasscode		Varchar(50)		= ''

    IF @ldetno = 0 OR @ldetno = NULL
		BEGIN
			INSERT INTO tblcompanyclasses(compcode, encodedby, dateencoded)
			VALUES(@lcompcode, @lencodedby, GETDATE())
			SELECT @ldetno = @@IDENTITY
		END

	SELECT @loldclasscode = classcode FROM tblcompanyclasses WITH(NOLOCK) WHERE detno = @ldetno

	UPDATE tblcompanyclasses
	SET templatetype		= @ltemplatetype,
		parentcompcode		= @lcompcode,
		contractcode		= @lcontractcode,
		effectivity			= @leffectivity,
		expiry				= @lexpiry,
		productcode			= @lproductcode,
		agefrom				= @lagefrom,
		ageto				= @lageto,
		agefromdep			= @lagefromdep,
		agetodep			= @lagetodep,
		classcode			= @lclasscode,
		classname			= @lclassname,
		classdesc			= @lclassdesc,
		ilbundled			= @lilbundled,
		topupplan			= @ltopupplan,
		grandfatheredplan	= @grandfatheredplan,
		coveragetype		= @lcoveragetype,
		dentalinformation	= @ldentalinformation
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	IF @ltemplatetype = 2
		BEGIN
			UPDATE tblcompanybenefitplan
			SET classcode = @lclasscode
			WHERE classcode = @loldclasscode AND compcode = 0 AND contractcode = 0
			OPTION(RECOMPILE)
		END

	SELECT @ldetno AS detno

END
GO

-- ---- sp_saveaccountclassesv6 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveaccountclassesv6]
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@compcode			Int,
	@parentcompcode		Int,
	@contractcode		Int,
	@productcode		Int,
	@templatetype		Int,
	@effectivity		Smalldatetime,
	@expiry				Smalldatetime,
	@agefrom			Numeric(3,0),
	@ageto				Numeric(3,0),
	@agefromdep			Numeric(3,0),
	@agetodep			Numeric(3,0),
	@classcode			Varchar(50),
	@classname			Varchar(150),
	@classdesc			Varchar(240),
	@ilbundled			Bit,
	@topupplan			Bit,
	@coveragetype		Tinyint,
	@grandfatheredplan	Bit,
	@encodedby			Int,
	@dentalinformation	Bit,
	@clinicbased		Bit

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldetno				Int				= @detno,
			@lcompcode			Int				= @compcode,
			@lparentcompcode	Int				= @parentcompcode,
			@lcontractcode		Int				= @contractcode,
			@leffectivity		Smalldatetime	= @effectivity,
			@lexpiry			Smalldatetime	= @expiry,
			@lproductcode		Int				= @productcode,
			@ltemplatetype		Int				= @templatetype,
			@lagefrom			Numeric(3,0)	= @agefrom,
			@lageto				Numeric(3,0)	= @ageto,
			@lagefromdep		Numeric(3,0)	= @agefromdep,
			@lagetodep			Numeric(3,0)	= @agetodep,
			@lclasscode			Varchar(50)		= @classcode,
			@lclassname			Varchar(150)	= @classname,
			@lclassdesc			Varchar(240)	= @classdesc,
			@lilbundled			Bit				= @ilbundled,
			@ltopupplan			Bit				= @topupplan,
			@lcoveragetype		Tinyint			= @coveragetype,
			@lgrandfatheredplan	Bit				= @grandfatheredplan,
			@lencodedby			Int				= @encodedby,
			@ldentalinformation	Bit				= @dentalinformation,
			@lclinicbased		Bit				= @clinicbased,
			@loldclasscode		Varchar(50)		= ''

    IF @ldetno = 0 OR @ldetno = NULL
		BEGIN
			INSERT INTO tblcompanyclasses(compcode, encodedby, dateencoded)
			VALUES(@lcompcode, @lencodedby, GETDATE())
			SELECT @ldetno = @@IDENTITY
		END

	SELECT @loldclasscode = classcode FROM tblcompanyclasses WITH(NOLOCK) WHERE detno = @ldetno

	UPDATE tblcompanyclasses
	SET templatetype		= @ltemplatetype,
		parentcompcode		= @lcompcode,
		contractcode		= @lcontractcode,
		effectivity			= @leffectivity,
		expiry				= @lexpiry,
		productcode			= @lproductcode,
		agefrom				= @lagefrom,
		ageto				= @lageto,
		agefromdep			= @lagefromdep,
		agetodep			= @lagetodep,
		classcode			= @lclasscode,
		classname			= @lclassname,
		classdesc			= @lclassdesc,
		ilbundled			= @lilbundled,
		topupplan			= @ltopupplan,
		grandfatheredplan	= @grandfatheredplan,
		coveragetype		= @lcoveragetype,
		dentalinformation	= @ldentalinformation,
		clinicbased			= @lclinicbased
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	IF @ltemplatetype = 2
		BEGIN
			UPDATE tblcompanybenefitplan
			SET classcode = @lclasscode
			WHERE classcode = @loldclasscode AND compcode = 0 AND contractcode = 0
			OPTION(RECOMPILE)
		END

	SELECT @ldetno AS detno

END
GO

-- ---- sp_saveaccountcontractyearsv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveaccountcontractyearsv2]
	-- Add the parameters for the stored procedure here
	
	@contractcode		Int,
	@compcode			Int,
	@effectivity		Smalldatetime,
	@expiry				Smalldatetime,
	@remarks			Varchar(200),
	@renewal			Bit,
	@preterm			Bit,
	@calendardays		Bit,
	@creditterm			Int,
	@modalcreditterm	Int,
	@madmembercount		Numeric(18,0),
	@madtotalamount		Numeric(18,2),
	@madtype			Int,
	@postedby			Int,
	@oldcontractcode	Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lcontractcode			Int				= @contractcode,
			@lcompcode				Int				= @compcode,
			@leffectivity			Smalldatetime	= @effectivity,
			@lexpiry				Smalldatetime	= @expiry,
			@lremarks				Varchar(200)	= @remarks,			
			@lrenewal				Bit				= @renewal,
			@lpreterm				Bit				= @preterm,
			@lcalendardays			Bit				= @calendardays,
			@lcreditterm			Int				= @creditterm,
			@lmodalcreditterm		Int				= @modalcreditterm,
			@lmadmembercount		Numeric(18,0)	= @madmembercount,
			@lmadtotalamount		Numeric(18,2)	= @madtotalamount,
			@lmadtype				Int				= @madtype,
			@lpostedby				Int				= @postedby,
			@loldcontractcode		Int				= @oldcontractcode

	IF @lcontractcode = NULL OR @lcontractcode = 0  
        BEGIN  
			INSERT INTO tblcompanycontractyears(dateposted, postedby, compcode) 
			VALUES(GETDATE(), @lpostedby, @lcompcode)
			SELECT @lcontractcode = @@IDENTITY
        END  
	
	IF @loldcontractcode IS NOT NULL AND @loldcontractcode > 0
	BEGIN
		UPDATE tblcompanycontractyears 
		SET renewalcontractcode = @lcontractcode
		WHERE contractcode = @loldcontractcode
	END

	UPDATE tblcompanycontractyears
	SET effectivity			= @leffectivity,
		expiry				= @lexpiry,
		remarks				= @lremarks,
		contractyearfrom	= YEAR(@leffectivity),
		contractyearto		= YEAR(@lexpiry),
		initial				= IIF(@lrenewal = 1, 0, 1),
		preterm				= @lpreterm,
		calendardays		= @lcalendardays,
		modalcreditterm		= @lmodalcreditterm
	WHERE contractcode = @lcontractcode
	OPTION(RECOMPILE)

	IF @lrenewal = 0
		BEGIN  
			UPDATE tblcompanycontractyears
			SET initialmadtype		= @lmadtype,
				initialmembercount	= @lmadmembercount,
				initialtotalamount	= @lmadtotalamount,
				initialcreditterm	= @lcreditterm
			WHERE contractcode = @lcontractcode
			OPTION(RECOMPILE)
		END
	ELSE
		BEGIN  
			UPDATE tblcompanycontractyears
			SET renewalmadtype 		= @lmadtype,
				renewalmembercount	= @lmadmembercount,
				renewaltotalamount	= @lmadtotalamount,
				renewalcreditterm	= @lcreditterm
			WHERE contractcode = @lcontractcode
			OPTION(RECOMPILE)
		END	

	SELECT @lcontractcode AS contractcode	

END
GO

-- ---- sp_saveaccountsettingspremium ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_saveaccountsettingspremium]
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@compcode			Int,
	@billclassdetno		Int,
	@premiumsetup		TinyInt,
	@refundsetup		TinyInt,
	@notmorethan15		Numeric(6,2),
	@morethan15			Numeric(6,2),
	@morethan1month		Numeric(6,2),
	@morethan2months	NUmeric(6,2)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldetno				Int				= @detno,
			@lcompcode			Int				= @compcode,
			@lbillclassdetno	Int				= @billclassdetno,
			@lpremiumsetup		TinyInt			= @premiumsetup,
			@lrefundsetup		TinyInt			= @refundsetup,
			@lnotmorethan15		Numeric(6,2)	= @notmorethan15,
			@lmorethan15		Numeric(6,2)	= @morethan15,
			@lmorethan1month	Numeric(6,2)	= @morethan1month,
			@lmorethan2months	Numeric(6,2)	= @morethan2months


    IF @ldetno = 0 OR @ldetno = NULL
		BEGIN
			INSERT INTO tblsettingspremium(compcode, billclassdetno)
			VALUES(@lcompcode, @lbillclassdetno)
			SELECT @ldetno = @@IDENTITY
		END

	UPDATE tblsettingspremium
	SET premiumsetup		= @lpremiumsetup,
		refundsetup			= @lrefundsetup,
		notmorethan15		= @lnotmorethan15,
		morethan15			= @lmorethan15,
		morethan1month		= @lmorethan1month,
		morethan2months		= @lmorethan2months
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	SELECT @ldetno AS detno

END
GO

-- ---- sp_saveaccountv6 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveaccountv6]

	@compcode					Int,
	@accountcode				Varchar(20),
	@manualcontractno			Bit,
	@agreementno				Varchar(20),
	@accounttype				Int,
	@accountgroup				Int,
	@initial					Varchar(240),
	@companyname				Varchar(240),
	@tinno						Varchar(20),
	@annivedate					Smalldatetime,
	@streetaddress				Varchar(100),
	@branchcode					Int,
	@citycode					Int,
	@provincecode				Int,
	@zipcode					Varchar(20),
	@officeno					Varchar(50),
	@faxno						Varchar(20),
	@website					Varchar(100),
	@effectivity				Smalldatetime,
	@expiry						Smalldatetime,
	@renewal					Bit,
	@calendardays				Bit,
	@creditterm					Int,
	@modalcreditterm			Int,
	@madmembercount				Numeric(18,0),
	@madtotalamount				Numeric(18,2),
	@madtype					Int,
	@vattype					Int,
	@cwtax						Numeric(6,2),
	@restrictmobile				Bit,
	@asoadminfeetype			Int,
	@asoadminfee				Numeric(18,2),
	@asoservicefeetype			Int,
	@asoservicefee				Numeric(18,2),
	@modalmonthly				Numeric(18,6),
	@modalquarterly				Numeric(18,2),
	@modalsemiannual			Numeric(18,2),
	@modalannual				Numeric(18,2),
	@premiumcaption				Varchar(100),
	@roundingoff				Int,
	@memberpremium				Int,
	@encodedby					Int,
	@allowmemberportal			Bit,
	@telemedicine				Bit,
	@memberportalaccessfrom		Smalldatetime,
	@memberportalaccessto		Smalldatetime,
	@wtaxno						Int,
	@wtax						Numeric(6,2),
	@enhancedencryption			Bit,
	@restrictdependentmobile	Bit,
	@maxcpddependent			Tinyint,
	@maxvpddependent			Tinyint

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
			
	DECLARE @lcompcode					Int				= @compcode,
			@laccountcode				Varchar(20)		= @accountcode,
			@lmanualcontractno			Bit				= @manualcontractno,		
			@lagreementno				Varchar(100)	= @agreementno,
			@laccounttype				Int				= @accounttype,
			@laccountgroup				Int				= @accountgroup,
			@linitial					Varchar(240)	= @initial,
			@lcompanyname				Varchar(240)	= @companyname,
			@ltinno						Varchar(20)		= @tinno,
			@lannivedate				Smalldatetime	= @annivedate,
			@lstreetaddress				Varchar(100)	= @streetaddress,
			@lbranchcode				Int				= @branchcode,
			@lcitycode					Int				= @citycode,
			@lprovincecode				Int				= @provincecode,
			@lzipcode					Varchar(20)		= @zipcode,
			@lofficeno					Varchar(50)		= @officeno,
			@lfaxno						Varchar(20)		= @faxno,
			@lwebsite					Varchar(100)	= @website,
			@lvattype					Int				= @vattype,
			@lcwtax						Numeric(6,2)	= @cwtax,
			@lrestrictmobile			Bit				= @restrictmobile,
			@lasoadminfeetype			Int				= @asoadminfeetype,
			@lasoadminfee				Numeric(18,2)	= @asoadminfee,
			@lasoservicefeetype			Int				= @asoservicefeetype,
			@lasoservicefee				Numeric(18,2)	= @asoservicefee,
			@lpremiumcaption			Varchar(100)	= @premiumcaption,
			@lroundingoff				Int				= @roundingoff,
			@lmemberpremium				Int				= @memberpremium,
			@leffectivity				Smalldatetime	= @effectivity,
			@lexpiry					Smalldatetime	= @expiry,	
			@lrenewal					Bit				= @renewal,
			@lcalendardays				Bit				= @calendardays,
			@lcreditterm				Int				= @creditterm,
			@lmodalcreditterm			Int				= @modalcreditterm,
			@lmadmembercount			Numeric(18,0)	= @madmembercount,
			@lmadtotalamount			Numeric(18,2)	= @madtotalamount,
			@lmadtype					Int				= @madtype,
			@lmodalmonthly				Numeric(18,6)	= @modalmonthly,
			@lmodalquarterly			Numeric(18,2)	= @modalquarterly,
			@lmodalsemiannual			Numeric(18,2)	= @modalsemiannual,
			@lmodalannual				Numeric(18,2)	= @modalannual,
			@lencodedby					Int				= @encodedby,
			@lseries					Int				= 0,
			@lcontractcode				Int				= 0,
			@lfactorcode				Int				= 0,
			@lallowmemberportal			Bit				= @allowmemberportal,
			@ltelemedicine				Bit				= @telemedicine,
			@lmemberportalaccessfrom	Smalldatetime	= @memberportalaccessfrom,
			@lmemberportalaccessto		Smalldatetime	= @memberportalaccessto,
			@lwtaxno					Int				= @wtaxno,
			@lwtax						Numeric(6,2)	= @wtax,
			@lenhancedencryption		Bit				= @enhancedencryption,
			@lrestrictdependentmobile	Bit				= @restrictdependentmobile,
			@lmaxcpddependent			Tinyint			= @maxcpddependent,
			@lmaxvpddependent			Tinyint			= @maxvpddependent

	DECLARE @KeyGUID UNIQUEIDENTIFIER 
	SET @KeyGUID = KEY_GUID('Encrypt')

	EXEC sp_opensymmetric

	IF @lcompcode = 0 OR @lcompcode = null
		BEGIN
			INSERT INTO tblcompany(companyname, encodedby, ldflog, dateencoded) 
			VALUES(ENCRYPTBYKEY(@KeyGUID, RTRIM(@lcompanyname)), @lencodedby, ISNULL(dbo.decoder(@lcompanyname, 1), ''), GETDATE()) 
			SELECT @lcompcode = @@IDENTITY 
		END

	IF @lmanualcontractno = 0	
		BEGIN
			INSERT INTO srsaccounts(primarykey) VALUES(@lcompcode) 
			SELECT @lseries = @@IDENTITY 

			SET @lagreementno = IIF(LEN(@lseries) < 6, RIGHT('000000'+LTRIM(RTRIM(CAST(@lseries AS VARCHAR))), 6), LTRIM(RTRIM(CAST(@lseries AS VARCHAR))))
		END

	UPDATE tblcompany
	SET companysetup			= 1,
		accountcode				= @laccountcode,
		contractno				= @lagreementno,
		manualcontractno		= @lmanualcontractno,
		companytype				= @laccounttype,
		accountgroup			= @laccountgroup,
		initial					= @linitial,
		companyname				= ENCRYPTBYKEY(@KeyGUID, RTRIM(@lcompanyname)),
		ldflog					= ISNULL(dbo.decoder(@lcompanyname, 1), ''),
		tinno					= @ltinno,
		dateenrolled			= @lannivedate,
		streetaddress			= @lstreetaddress,
		citycode				= @lcitycode,
		provincecode			= @lprovincecode,
		zipcode					= @lzipcode,
		branch					= @lbranchcode,
		telephone				= @lofficeno,
		website					= @lwebsite,
		fax						= @lfaxno,
		renewal					= @lrenewal,
		effectivity				= @leffectivity,
		expiry					= @lexpiry,
		coveredfrom				= @leffectivity,
		coveredto				= @lexpiry,
		vattype					= @lvattype,
		cwtax					= @lcwtax,
		restrictmobile			= @lrestrictmobile,
		asoadminfee				= @lasoadminfee,
		asoadminfeetype			= @lasoadminfeetype,
		asoservicefee			= @lasoservicefee,
		asoservicefeetype		= @lasoservicefeetype,
		premiumcaption			= @lpremiumcaption,
		roundingoff				= @lroundingoff,
		memberpremium			= @lmemberpremium,
		allowmemberportal		= @lallowmemberportal,
		telemedicine			= @ltelemedicine,
		memberportalaccessfrom	= @lmemberportalaccessfrom,
		memberportalaccessto	= @lmemberportalaccessto,
		wtaxno					= @lwtaxno,
		wtax					= @lwtax,
		enhancedencryption		= @lenhancedencryption,
		restrictdependentmobile = @lrestrictdependentmobile,
		maxcpddependent			= @lmaxcpddependent,
		maxvpddependent			= @lmaxvpddependent
	WHERE compcode = @lcompcode
	OPTION(RECOMPILE)

	INSERT INTO tblcompanycontractyears(dateposted, postedby, compcode) 
	VALUES(GETDATE(), @lencodedby, @lcompcode)
	SELECT @lcontractcode = @@IDENTITY

	UPDATE tblcompanycontractyears
	SET effectivity			= @leffectivity,
		expiry				= @lexpiry,
		contractyearfrom	= YEAR(@leffectivity),
		contractyearto		= YEAR(@lexpiry),
		initial				= Iif(@lrenewal = 0, 1, 0),
		calendardays		= @lcalendardays,
		modalcreditterm		= @lmodalcreditterm
		--initialmadtype		= @lmadtype,
		--initialmembercount	= @lmadmembercount,
		--initialtotalamount	= @lmadtotalamount,
		--initialcreditterm	= @lcreditterm
	WHERE contractcode = @lcontractcode
	OPTION(RECOMPILE)
	
	IF @lrenewal = 0
		BEGIN  
			UPDATE tblcompanycontractyears
			SET initialmadtype		= @lmadtype,
				initialmembercount	= @lmadmembercount,
				initialtotalamount	= @lmadtotalamount,
				initialcreditterm	= @lcreditterm
			WHERE contractcode = @lcontractcode
			OPTION(RECOMPILE)
		END
	ELSE
		BEGIN  
			UPDATE tblcompanycontractyears
			SET renewalmadtype 		= @lmadtype,
				renewalmembercount	= @lmadmembercount,
				renewaltotalamount	= @lmadtotalamount,
				renewalcreditterm	= @lcreditterm
			WHERE contractcode = @lcontractcode
			OPTION(RECOMPILE)
		END	
	

	INSERT INTO tblcompanymodalfactor(compcode, effectivity, dateencoded, encodedby) 
	VALUES(@lcompcode, @leffectivity, GETDATE(), @lencodedby)
	SELECT @lfactorcode = @@IDENTITY

	UPDATE tblcompanymodalfactor
	SET monthly		= @lmodalmonthly,
		quarterly	= @lmodalquarterly,
		semiannual	= @lmodalsemiannual,
		annual		= @lmodalannual
	WHERE factorcode = @lfactorcode

	EXEC sp_closesymmetric
	SELECT @lcompcode AS compcode, @lagreementno AS agreementno, @lcontractcode AS contractcode
END



GO

-- ---- sp_saveaffiliateaccountv4 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_saveaffiliateaccountv4] --'', '', '', '', '', '', 0, 0, 99, '', '', 1, 0

	@parentcompcode			Int,
	@compcode				Int,
	@accountcode			Varchar(20),
	@manualcontractno		Bit,
	@agreementno			Varchar(20),
	@accounttype			Int,
	@initial				Varchar(20),
	@companyname			Varchar(100),
	@tinno					Varchar(20),
	@annivedate				Smalldatetime,
	@streetaddress			Varchar(100),
	@branchcode				Int,
	@citycode				Int,
	@provincecode			Int,
	@zipcode				Varchar(20),
	@officeno				Varchar(50),
	@faxno					Varchar(20),
	@website				Varchar(100),
	@effectivity			Smalldatetime,
	@expiry					Smalldatetime,
	@renewal				Bit,
	@calendardays			Bit,
	@creditterm				Int,
	@modalcreditterm		Int,
	@madmembercount			Numeric(18,0),
	@madtotalamount			Numeric(18,2),
	@madtype				Int,
	@vattype				Int,
	@cwtax					Numeric(6,2),
	@restrictmobile			Bit,
	@asoadminfeetype		Int,
	@asoadminfee			Numeric(18,2),
	@asoservicefeetype		Int,
	@asoservicefee			Numeric(18,2),
	@modalmonthly			Numeric(18,6),
	@modalquarterly			Numeric(18,2),
	@modalsemiannual		Numeric(18,2),
	@modalannual			Numeric(18,2),
	@premiumcaption			Varchar(100),
	@roundingoff			Int,
	@memberpremium			Int,
	@encodedby				Int,
	@allowmemberportal		Bit,
	@memberportalaccessfrom	Smalldatetime,
	@memberportalaccessto	Smalldatetime,
	@enhancedencryption		Bit,
	@restrictdependentmobile	Bit,
	@telemedicine			Bit

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
			
	DECLARE @lparentcompcode			Int				= @parentcompcode,
			@lcompcode					Int				= @compcode,
			@laccountcode				Varchar(20)		= @accountcode,
			@lmanualcontractno			Bit				= @manualcontractno,		
			@lagreementno				Varchar(100)	= @agreementno,
			@laccounttype				Int				= @accounttype,
			@linitial					Varchar(20)		= @initial,
			@lcompanyname				Varchar(100)	= @companyname,
			@ltinno						Varchar(20)		= @tinno,
			@lannivedate				Smalldatetime	= @annivedate,
			@lstreetaddress				Varchar(100)	= @streetaddress,
			@lbranchcode				Int				= @branchcode,
			@lcitycode					Int				= @citycode,
			@lprovincecode				Int				= @provincecode,
			@lzipcode					Varchar(20)		= @zipcode,
			@lofficeno					Varchar(50)		= @officeno,
			@lfaxno						Varchar(20)		= @faxno,
			@lwebsite					Varchar(100)	= @website,
			@lvattype					Int				= @vattype,
			@lcwtax						Numeric(6,2)	= @cwtax,
			@lrestrictmobile			Bit				= @restrictmobile,
			@lasoadminfeetype			Int				= @asoadminfeetype,
			@lasoadminfee				Numeric(18,2)	= @asoadminfee,
			@lasoservicefeetype			Int				= @asoservicefeetype,
			@lasoservicefee				Numeric(18,2)	= @asoservicefee,
			@lpremiumcaption			Varchar(100)	= @premiumcaption,
			@lroundingoff				Int				= @roundingoff,
			@lmemberpremium				Int				= @memberpremium,
			@leffectivity				Smalldatetime	= @effectivity,
			@lexpiry					Smalldatetime	= @expiry,	
			@lrenewal					Bit				= @renewal,
			@lcalendardays				Bit				= @calendardays,
			@lcreditterm				Int				= @creditterm,
			@lmodalcreditterm			Int				= @modalcreditterm,
			@lmadmembercount			Numeric(18,0)	= @madmembercount,
			@lmadtotalamount			Numeric(18,2)	= @madtotalamount,
			@lmadtype					Int				= @madtype,
			@lmodalmonthly				Numeric(18,6)	= @modalmonthly,
			@lmodalquarterly			Numeric(18,2)	= @modalquarterly,
			@lmodalsemiannual			Numeric(18,2)	= @modalsemiannual,
			@lmodalannual				Numeric(18,2)	= @modalannual,
			@lencodedby					Int				= @encodedby,
			@lallowmemberportal			Bit				= @allowmemberportal,
			@lmemberportalaccessfrom	Smalldatetime	= @memberportalaccessfrom,
			@lmemberportalaccessto		Smalldatetime	= @memberportalaccessto,
			@lenhancedencryption		Bit				= @enhancedencryption,
			@lseries					Int				= 0,
			@lcontractcode				Int				= 0,
			@lfactorcode				Int				= 0,
			@lparentcontractno			Varchar(100)	= '',
			@lcount						Int				= 0,
			@lrestrictdependentmobile	Bit				= @restrictdependentmobile,
			@ltelemedicine				Bit				= @telemedicine

	DECLARE @KeyGUID UNIQUEIDENTIFIER 
	SET @KeyGUID = KEY_GUID('Encrypt')

	EXEC sp_opensymmetric

	--IF (@lagreementno = NULL OR @lagreementno = '')
		--BEGIN
	--SELECT @lparentcontractno = LTRIM(RTRIM(contractno)) FROM tblcompany WHERE compcode = @lparentcompcode
	--OPTION(RECOMPILE)

	--SELECT @lcount = ISNULL(COUNT(compcode), 0) + 1 FROM tblcompany WHERE parentcompcode <> 0 AND parentcompcode = @lparentcompcode
	--OPTION(RECOMPILE)

	--SET @lagreementno = @lparentcontractno + '-' + CAST(@lcount AS varchar(10))
		--END

	INSERT INTO tblcompany(companyname, encodedby, ldflog, parentcompcode, dateencoded) 
	VALUES(ENCRYPTBYKEY(@KeyGUID, RTRIM(@lcompanyname)), @lencodedby, ISNULL(dbo.decodercontains(@lcompanyname, 1), ''), @lparentcompcode, GETDATE()) 
	SELECT @lcompcode = @@IDENTITY 

	UPDATE tblcompany
	SET companysetup		= 3,
		accountcode			= @laccountcode,
		contractno			= @lagreementno,
		manualcontractno	= @lmanualcontractno,
		companytype			= @laccounttype,
		initial				= @linitial,
		companyname			= ENCRYPTBYKEY(@KeyGUID, RTRIM(@lcompanyname)),
		ldflog				= ISNULL(dbo.decoder(@lcompanyname, 1), ''),
		tinno				= @ltinno,
		dateenrolled		= @lannivedate,
		streetaddress		= @lstreetaddress,
		citycode			= @lcitycode,
		provincecode		= @lprovincecode,
		zipcode				= @lzipcode,
		branch				= @lbranchcode,
		telephone			= @lofficeno,
		website				= @lwebsite,
		fax					= @lfaxno,
		renewal				= @lrenewal,
		effectivity			= @leffectivity,
		expiry				= @lexpiry,
		coveredfrom			= @leffectivity,
		coveredto			= @lexpiry,
		vattype				= @lvattype,
		cwtax				= @lcwtax,
		restrictmobile		= @lrestrictmobile,
		asoadminfee			= @lasoadminfee,
		asoadminfeetype		= @lasoadminfeetype,
		asoservicefee		= @lasoservicefee,
		asoservicefeetype	= @lasoservicefeetype,
		premiumcaption		= @lpremiumcaption,
		roundingoff			= @lroundingoff,
		memberpremium		= @lmemberpremium,
		allowmemberportal		= @lmemberpremium,
		memberportalaccessfrom	= @lmemberportalaccessfrom,
		memberportalaccessto	= @lmemberportalaccessto,
		enhancedencryption		= @enhancedencryption,
		restrictdependentmobile	= @lrestrictdependentmobile,
		telemedicine			= @ltelemedicine
	WHERE compcode = @lcompcode
	OPTION(RECOMPILE)

	UPDATE tblcompany SET companysetup = 2 WHERE compcode = @lparentcompcode
	OPTION(RECOMPILE)

	INSERT INTO tblcompanycontractyears(dateposted, postedby, compcode) 
	VALUES(GETDATE(), @lencodedby, @lcompcode)
	SELECT @lcontractcode = @@IDENTITY

	UPDATE tblcompanycontractyears
	SET effectivity			= @leffectivity,
		expiry				= @lexpiry,
		contractyearfrom	= YEAR(@leffectivity),
		contractyearto		= YEAR(@lexpiry),
		initial				= Iif(@lrenewal = 0, 1, 0),
		calendardays		= @lcalendardays,
		modalcreditterm		= @lmodalcreditterm
		--initialmadtype		= @lmadtype,
		--initialmembercount	= @lmadmembercount,
		--initialtotalamount	= @lmadtotalamount,
		--initialcreditterm	= @lcreditterm
	WHERE contractcode = @lcontractcode
	OPTION(RECOMPILE)
	
	IF @lrenewal = 0
		BEGIN  
			UPDATE tblcompanycontractyears
			SET initialmadtype		= @lmadtype,
				initialmembercount	= @lmadmembercount,
				initialtotalamount	= @lmadtotalamount,
				initialcreditterm	= @lcreditterm
			WHERE contractcode = @lcontractcode
			OPTION(RECOMPILE)
		END
	ELSE
		BEGIN  
			UPDATE tblcompanycontractyears
			SET renewalmadtype 		= @lmadtype,
				renewalmembercount	= @lmadmembercount,
				renewaltotalamount	= @lmadtotalamount,
				renewalcreditterm	= @lcreditterm
			WHERE contractcode = @lcontractcode
			OPTION(RECOMPILE)
		END	

	INSERT INTO tblcompanymodalfactor(compcode, effectivity, dateencoded, encodedby) 
	VALUES(@lcompcode, @leffectivity, GETDATE(), @lencodedby)
	SELECT @lfactorcode = @@IDENTITY

	UPDATE tblcompanymodalfactor
	SET monthly		= @lmodalmonthly,
		quarterly	= @lmodalquarterly,
		semiannual	= @lmodalsemiannual,
		annual		= @lmodalannual
	WHERE factorcode = @lfactorcode
	OPTION(RECOMPILE)

	EXEC sp_closesymmetric

	SELECT @lcompcode AS compcode, @lcontractcode AS contractcode

END



GO

-- ---- sp_saveamendeffectivity ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_saveamendeffectivity]
	-- Add the parameters for the stored procedure here
	
	@compcode			Int,
	@membercode			Int,
	@effectivity		Smalldatetime,
	@billingschedule	Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lcompcode			Int				= @compcode,
			@lmembercode		Int				= @membercode,
			@leffectivity		Smalldatetime	= @effectivity,
			@lbillingschedule	Int				= @billingschedule,
			@lcurr_eff			Smalldatetime	= '1/1/1900',
			@lmodalfrom			Smalldatetime	= '1/1/1900',
			@lmodalto			Smalldatetime	= '1/1/1900',
			@lmonths			Int				= 0

	SELECT @lcurr_eff = effectivity
	FROM tblmembers WITH(NOLOCK)
	WHERE compcode = @lcompcode
	AND membercode = @lmembercode
	OPTION(RECOMPILE)

	SELECT
	@lmodalfrom = modalfrom,
	@lmodalto = modalto
	FROM tblmemberuploaddetails WITH(NOLOCK)
	WHERE compcode = @lcompcode
	AND membercode = @lmembercode
	AND effectivity = @lcurr_eff
	OPTION(RECOMPILE)

	SET @lmonths = CASE @lbillingschedule
				   WHEN 1 THEN 1
				   WHEN 2 THEN 3
				   WHEN 3 THEN 6
				   WHEN 4 THEN 12
				   ELSE 0 END

	IF @lmodalfrom <> '1/1/1900' AND @lcurr_eff <> @leffectivity
	BEGIN
		
		WHILE @lmodalto < @leffectivity
		BEGIN
			SET @lmodalfrom = DATEADD(DAY, 1, @lmodalto)
			SET @lmodalto = DATEADD(DAY, -1, DATEADD(MONTH, @lmonths, @lmodalfrom))
		END

		UPDATE a SET 
		effectivity = @effectivity,
		modalfrom = @lmodalfrom,
		modalto = @lmodalto
		FROM tblmemberuploaddetails a WITH(NOLOCK) 
		WHERE a.compcode = @lcompcode
		AND a.membercode = @lmembercode
		AND a.effectivity = @lcurr_eff
		OPTION(RECOMPILE)

	END

END
GO

-- ---- sp_saveapplicationdependentv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveapplicationdependentv2] --'', '', '', '', '', '', 0, 0, 99, '', '', 1, 0

	@applicationcode		Int,
	@apprincode				Int,
	@membername				Varchar(240),
	@lastname				Varchar(100),
	@firstname				Varchar(100),
	@miname					Varchar(20),
	@suffix					Varchar(10),
	@birthdate				Smalldatetime,
	@benefitclass			Varchar(50),
	@premiumclass			Varchar(50),
	@membercategory			Varchar(5),
	@height					Numeric(6,2),
	@weight					Numeric(6,2),
	@bmicategory			Numeric(6,2),
	@bmiresult				Varchar(30),
	@emailaddress			Varchar(100),
	@annualpremiumfee		Numeric(18,2),
	@premiumfee				Numeric(18,2),
	@nonpremiumfee			Numeric(18,2),
	@originalfee			Numeric(18,2),
	@originalnonfee			Numeric(18,2),
	@gender					Varchar(10),
	@civilstatus			Tinyint,
	@applicationdate		Smalldatetime,
	@sssno					Varchar(20),
	@tin					Varchar(20),
	@telephone				Varchar(100),
	@mobile					Varchar(20),	
	@billingschedule		Int,
	@renewal				Bit,
	@withphilhealth			Bit,
	@memberno				Varchar(20),
	@membersince			Smalldatetime,
	@provideraccess			Int,
	@dental					Int,
	@onetimefee				Bit,
	@pecwaived				Bit,
	@withtelemedicine		Bit,
	@dependenttype			Tinyint,
	@medicalstatus			TinyInt,
	@status					TinyInt,
	@picturename			Varchar(80),
	@sacode					Int,
	@productcode			Int,
	@nomedicaldeclaration	Bit,
	@specialrate			Numeric(18,2),
	@medicalby				Int,	
	@encodedby				Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
			
	DECLARE @lapplicationcode		Int				= @applicationcode,
			@lapprincode			Int				= @apprincode,
			@lmembername			Varchar(240)	= @membername,
			@llastname				Varchar(100)	= @lastname,
			@lfirstname				Varchar(100)	= @firstname,
			@lminame				Varchar(20)		= @miname,
			@lsuffix				Varchar(10)		= @suffix,
			@lbirthdate				Smalldatetime	= @birthdate,
			@lheight				Numeric(6,2)	= @height,
			@lweight				Numeric(6,2)	= @weight,
			@lbenefitclass			Varchar(50)		= @benefitclass,
			@lpremiumclass			Varchar(50)		= @premiumclass,
			@lbmicategory			Numeric(6,2)	= @bmicategory,
			@lbmiresult				Varchar(30)		= @bmiresult,
			@lgender				Varchar(10)		= @gender,
			@lcivilstatus			Tinyint			= @civilstatus,
			@lsssno					Varchar(20)		= @sssno,
			@ltin					Varchar(20)		= @tin,
			@lannualpremiumfee		Numeric(18,2)	= @annualpremiumfee,
			@lpremiumfee			Numeric(18,2)	= @premiumfee,
			@lnonpremiumfee			Numeric(18,2)	= @nonpremiumfee,		
			@loriginalfee			Numeric(18,2)	= @originalfee,
			@loriginalnonfee		Numeric(18,2)	= @originalnonfee,
			@lmembercategory		Varchar(5)		= @membercategory,
			@lbillingschedule		Int				= @billingschedule,
			@lapplicationdate		Smalldatetime	= @applicationdate,
			@lemailaddress			Varchar(100)	= @emailaddress,
			@ltelephone				Varchar(100)	= @telephone,
			@lmobile				Varchar(20)		= @mobile,			
			@lrenewal				Bit				= @renewal,
			@lmemberno				Varchar(20)		= @memberno,
			@lmembersince			Smalldatetime	= @membersince,			
			@lprovideraccess		Int				= @provideraccess,
			@ldental				Int				= @dental,
			@lonetimefee			Bit				= @onetimefee,
			@lwithphilhealth		Bit				= @withphilhealth,
			@lpecwaived				Bit				= @pecwaived,
			@lwithtelemedicine		Bit				= @withtelemedicine,
			@lmedicalby				Int				= @medicalby,
			@lpicturename			Varchar(80)		= @picturename,
			@lmedicalstatus			TinyInt			= @medicalstatus,
			@ldependenttype			Tinyint			= @dependenttype,
			@lsacode				Int				= @sacode,
			@lproductcode			Int				= @productcode,
			@lnomedicaldeclaration	Bit				= @nomedicaldeclaration,
			@lspecialrate			Numeric(18,2)	= @specialrate,
			@lstatus				TinyInt			= @status,
			@lencodedby				Int				= @encodedby,
			@lapplicationno			Varchar(20)		= ''

	DECLARE @KeyGUID UNIQUEIDENTIFIER 
	SET @KeyGUID = KEY_GUID('Encrypt')

	EXEC sp_opensymmetric

	IF @lapplicationcode = 0 OR @lapplicationcode = null
		BEGIN
			INSERT INTO tblapplications(dateencoded, encodedby, principalcode, appprincode) VALUES(GETDATE(), @lencodedby, @lapprincode, @lapprincode)
			SELECT @lapplicationcode = @@IDENTITY 

			SET @lapplicationno = SUBSTRING(CAST(YEAR(GETDATE()) AS VARCHAR(4)),3,2) + RIGHT('00'+SUBSTRING(CAST(MONTH(GETDATE()) AS VARCHAR(2)),1,2),2) + '-'+ RIGHT('00000'+LTRIM(RTRIM(CAST(@lapplicationcode AS VARCHAR))), 5)
			UPDATE tblapplications set applicationno = @lapplicationno WHERE applicationcode = @lapplicationcode 
		END

		
	UPDATE tblapplications
	SET classorder			= 1,
		medicalstatus		= @lmedicalstatus,
		statuscode			= @lstatus,
		membertype			= 'R',
		membername			= ENCRYPTBYKEY(@KeyGUID, RTRIM(@lmembername)),
		lastname			= ENCRYPTBYKEY(@KeyGUID, RTRIM(@llastname)),
		firstname			= ENCRYPTBYKEY(@KeyGUID, RTRIM(@lfirstname)),
		mdflog				= ISNULL(dbo.decodercontains(@lmembername, 1), ''),
		llog				= ISNULL(dbo.decodercontains(@llastname, 1), ''),
		flog				= ISNULL(dbo.decodercontains(@lfirstname, 1), ''),
		miname				= dbo.Encrypt(@lminame),
		suffix 				= @lsuffix,
		birthdate 			= @lbirthdate,
		height 				= @lheight,
		weight 				= @lweight,
		benefitclass		= @lbenefitclass,
		premiumclass		= @lpremiumclass,
		bmicategory 		= @lbmicategory,
		bmiresult			= @lbmiresult,
		gender 				= @lgender,
		civilstatus			= @lcivilstatus,
		sssno 				= @lsssno,
		tin 				= @ltin,
		annualpremiumfee	= @lannualpremiumfee,
		premiumfee			= @lpremiumfee,
		nonpremiumfee		= @lnonpremiumfee,
		originalfee			= @loriginalfee,
		originalnonfee		= @loriginalnonfee,
		membercategory		= @lmembercategory,
		billingschedule		= @lbillingschedule,
		applicationdate		= @lapplicationdate,
		emailaddress		= dbo.Encrypt(@lemailaddress),
		telephone			= @ltelephone,
		mobile				= dbo.Encrypt(@lmobile),
		sacode				= @lsacode,
		productcode			= @lproductcode,
		nomedicaldeclaration = @lnomedicaldeclaration,
		specialrate			= @lspecialrate,
		renewal				= @lrenewal,
		memberno			= @lmemberno,
		membersince			= @lmembersince,
		provideraccess		= @lprovideraccess,
		dental				= @ldental,
		onetimefee			= @lonetimefee,
		withphilhealth		= @lwithphilhealth,
		pecwaived			= @lpecwaived,
		withtelemedicine	= @lwithtelemedicine,
		medicalby			= @lmedicalby,
		picturename			= @lpicturename,
		dependenttype		= @ldependenttype
	WHERE applicationcode = @lapplicationcode
	OPTION(RECOMPILE)

	SELECT @lapplicationcode AS applicationcode, @lapplicationno AS applicationno
END



GO

-- ---- sp_saveapplicationv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveapplicationv2] --'', '', '', '', '', '', 0, 0, 99, '', '', 1, 0

	@applicationcode		Int,
	@membername				Varchar(240),
	@lastname				Varchar(100),
	@firstname				Varchar(100),
	@miname					Varchar(20),
	@suffix					Varchar(10),
	@birthdate				Smalldatetime,
	@height					Numeric(6,2),
	@weight					Numeric(6,2),
	@bmicategory			Numeric(6,2),
	@bmiresult				Varchar(30),
	@gender					Varchar(10),
	@civilstatus			Tinyint,
	@sssno					Varchar(20),
	@tin					Varchar(20),
	@agentno				Int,
	@annualpremiumfee		Numeric(18,2),
	@premiumfee				Numeric(18,2),
	@nonpremiumfee			Numeric(18,2),
	@originalfee			Numeric(18,2),
	@originalnonfee			Numeric(18,2),
	@benefitclass			Varchar(50),
	@premiumclass			Varchar(50),
	@membercategory			Varchar(5),
	@billingschedule		Int,
	@applicationdate		Smalldatetime,
	@employer				Varchar(100),
	@employeeno				Varchar(20),
	@monthlyfamincome		Varchar(100),
	@occupation				Varchar(80),
	@newoccupation			Varchar(100),
	@emailaddress			Varchar(100),
	@telephone				Varchar(100),
	@mobile					Varchar(20),
	@officephone			Varchar(20),
	@officefax				Varchar(20),
	@datehired				Smalldatetime,
	@billingstreet			Varchar(100),
	@billingcity			Smallint,
	@billingprovince		Smallint,
	@zipcodebilling			Varchar(10),
	@homestreet				Varchar(100),
	@homecity				Smallint,
	@homeprovince			Smallint,
	@zipcodehome			Varchar(10),
	@billto					Tinyint,
	@sacode					Int,
	@productcode			Int,
	@specialrate			Numeric(18,2),
	@nomedicaldeclaration	Bit,
	@onlineapp				Bit,
	@renewal				Bit,
	@memberno				Varchar(20),
	@membersince			Smalldatetime,
	@discountrate			Numeric(6,2),
	@payorcode				Int,
	@payorname				Varchar(100),
	@businessstyle			Varchar(50),
	@branch					Int,
	@payortin				Varchar(20),
	@provideraccess			Int,
	@dental					Int,
	@onetimefee				Bit,
	@withphilhealth			Bit,
	@pecwaived				Bit,
	@withtelemedicine		Bit,
	@medicalby				Int,
	@picturename			Varchar(80),
	@medicalstatus			TinyInt,
	@status					TinyInt,
	@encodedby				Int,
	@payorrelationship1		TinyInt,
	@payorrelationship2		Varchar(80)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
			
	DECLARE @lapplicationcode		Int				= @applicationcode,
			@lmembername			Varchar(240)	= @membername,
			@llastname				Varchar(100)	= @lastname,
			@lfirstname				Varchar(100)	= @firstname,
			@lminame				Varchar(20)		= @miname,
			@lsuffix				Varchar(10)		= @suffix,
			@lbirthdate				Smalldatetime	= @birthdate,
			@lheight				Numeric(6,2)	= @height,
			@lweight				Numeric(6,2)	= @weight,
			@lbmicategory			Numeric(6,2)	= @bmicategory,
			@lbmiresult				Varchar(30)		= @bmiresult,
			@lgender				Varchar(10)		= @gender,
			@lcivilstatus			Tinyint			= @civilstatus,
			@lsssno					Varchar(20)		= @sssno,
			@ltin					Varchar(20)		= @tin,
			@lagentno				Int				= @agentno,
			@lannualpremiumfee		Numeric(18,2)	= @annualpremiumfee,
			@lpremiumfee			Numeric(18,2)	= @premiumfee,
			@lnonpremiumfee			Numeric(18,2)	= @nonpremiumfee,		
			@loriginalfee			Numeric(18,2)	= @originalfee,
			@loriginalnonfee		Numeric(18,2)	= @originalnonfee,
			@lbenefitclass			Varchar(50)		= @benefitclass,
			@lpremiumclass			Varchar(50)		= @premiumclass,
			@lmembercategory		Varchar(5)		= @membercategory,
			@lbillingschedule		Int				= @billingschedule,
			@lapplicationdate		Smalldatetime	= @applicationdate,
			@lemployer				Varchar(100)	= @employer,
			@lemployeeno			Varchar(20)		= @employeeno,
			@lmonthlyfamincome		Varchar(100)	= @monthlyfamincome,
			@loccupation			Varchar(80)		= @occupation,
			@lnewoccupation			Varchar(80)		= @newoccupation,
			@lemailaddress			Varchar(100)	= @emailaddress,
			@ltelephone				Varchar(100)	= @telephone,
			@lmobile				Varchar(20)		= @mobile,
			@lofficephone			Varchar(20)		= @officephone,
			@lofficefax				Varchar(20)		= @officefax,
			@ldatehired				Smalldatetime	= @datehired,
			@lbillingstreet			Varchar(100)	= @billingstreet,
			@lbillingcity			Smallint		= @billingcity,
			@lbillingprovince		Smallint		= @billingprovince,
			@lzipcodebilling		Varchar(10)		= @zipcodebilling,
			@lhomestreet			Varchar(100)	= @homestreet,
			@lhomecity				Smallint		= @homecity,
			@lhomeprovince			Smallint		= @homeprovince,
			@lzipcodehome			Varchar(10)		= @zipcodehome,
			@lbillto				Tinyint			= @billto,
			@lsacode				Int				= @sacode,
			@lproductcode			Int				= @productcode,
			@lspecialrate			Numeric(18,2)	= @specialrate,
			@lnomedicaldeclaration	Bit				= @nomedicaldeclaration,
			@lonlineapp				Bit				= @onlineapp,
			@lrenewal				Bit				= @renewal,
			@lmemberno				Varchar(20)		= @memberno,
			@lmembersince			Smalldatetime	= @membersince,
			@ldiscountrate			Numeric(6,2)	= @discountrate,
			@lpayorcode				Int				= @payorcode,
			@lpayorname				Varchar(100)	= @payorname,
			@lbusinessstyle			Varchar(50)		= @businessstyle,
			@lbranch				Int				= @branch,
			@lpayortin				Varchar(20)		= @payortin,
			@lprovideraccess		Int				= @provideraccess,
			@ldental				Int				= @dental,
			@lonetimefee			Bit				= @onetimefee,
			@lwithphilhealth		Bit				= @withphilhealth,
			@lpecwaived				Bit				= @pecwaived,
			@lwithtelemedicine		Bit				= @withtelemedicine,
			@lmedicalby				Int				= @medicalby,
			@lpicturename			Varchar(80)		= @picturename,
			@lmedicalstatus			TinyInt			= @medicalstatus,
			@lstatus				TinyInt			= @status,
			@lencodedby				Int				= @encodedby,
			@lpayorrelationship1	TinyInt			= @payorrelationship1,
			@lpayorrelationship2	Varchar(80)		= @payorrelationship2,
			@lapplicationno			Varchar(20)		= ''

	DECLARE @KeyGUID UNIQUEIDENTIFIER 
	SET @KeyGUID = KEY_GUID('Encrypt')

	EXEC sp_opensymmetric

	IF @lapplicationcode = 0 OR @lapplicationcode = null
		BEGIN
			INSERT INTO tblapplications(dateencoded, encodedby) VALUES(GETDATE(), @lencodedby)
			SELECT @lapplicationcode = @@IDENTITY 
			
			SET @lapplicationno = SUBSTRING(CAST(YEAR(GETDATE()) AS VARCHAR(4)),3,2) + RIGHT('00'+SUBSTRING(CAST(MONTH(GETDATE()) AS VARCHAR(2)),1,2),2) + '-'+ RIGHT('00000'+LTRIM(RTRIM(CAST(@lapplicationcode AS VARCHAR))), 5)
			
			UPDATE tblapplications SET applicationno = @lapplicationno
			WHERE applicationcode = @lapplicationcode
		END


	UPDATE tblapplications
	SET medicalstatus		= @lmedicalstatus,
		statuscode			= @lstatus,
		membertype			= 'R',
		membername			= ENCRYPTBYKEY(@KeyGUID, RTRIM(@lmembername)),
		lastname			= ENCRYPTBYKEY(@KeyGUID, RTRIM(@llastname)),
		firstname			= ENCRYPTBYKEY(@KeyGUID, RTRIM(@lfirstname)),
		mdflog				= ISNULL(dbo.decodercontains(@lmembername, 1), ''),
		llog				= ISNULL(dbo.decodercontains(@llastname, 1), ''),
		flog				= ISNULL(dbo.decodercontains(@lfirstname, 1), ''),
		miname				= dbo.Encrypt(@lminame),
		suffix 				= @lsuffix,
		birthdate 			= @lbirthdate,
		height 				= @lheight,
		weight 				= @lweight,
		benefitclass		= @lbenefitclass,
		premiumclass		= @lpremiumclass,
		bmicategory 		= @lbmicategory,
		bmiresult			= @lbmiresult,
		gender 				= @lgender,
		civilstatus			= @lcivilstatus,
		sssno 				= @lsssno,
		tin 				= @ltin,
		agentno				= @lagentno,
		annualpremiumfee	= @lannualpremiumfee,
		premiumfee			= @lpremiumfee,
		nonpremiumfee		= @lnonpremiumfee,
		originalfee			= @loriginalfee,
		originalnonfee		= @loriginalnonfee,
		membercategory		= @lmembercategory,
		billingschedule		= @lbillingschedule,
		--applicationno 		= @lapplicationno,
		applicationdate		= @lapplicationdate,
		employer			= @lemployer,
		employeeno			= @lemployeeno,
		monthlyfamilyincome	= @lmonthlyfamincome,
		occupation			= @loccupation,
		newoccupation		= @lnewoccupation,
		emailaddress		= dbo.Encrypt(@lemailaddress),
		telephone			= @ltelephone,
		mobile				= dbo.Encrypt(@lmobile),
		officephone			= @lofficephone,
		officefax			= @lofficefax,
		datehired			= @ldatehired,
		billingstreet		= @lbillingstreet,
		billingcity			= @lbillingcity,
		billingprovince		= @lbillingprovince,
		zipcodebilling		= @lzipcodebilling,
		homestreet			= @lhomestreet,
		homecity 			= @lhomecity,
		homeprovince		= @lhomeprovince,
		zipcodehome			= @lzipcodehome,
		billto				= @lbillto,
		sacode				= @lsacode,
		productcode			= @lproductcode,
		specialrate			= @lspecialrate,
		nomedicaldeclaration = @lnomedicaldeclaration,
		onlineapp			= @lonlineapp,
		renewal				= @lrenewal,
		memberno			= @lmemberno,
		membersince			= @lmembersince,
		discountrate		= @ldiscountrate,
		payorcode			= @lpayorcode,
		payorname			= @lpayorname,
		businessstyle		= @lbusinessstyle,
		branch				= @lbranch,
		payortin			= @lpayortin,
		provideraccess		= @lprovideraccess,
		dental				= @ldental,
		onetimefee			= @lonetimefee,
		withphilhealth		= @lwithphilhealth,
		pecwaived			= @lpecwaived,
		withtelemedicine	= @lwithtelemedicine,
		medicalby			= @lmedicalby,
		picturename			= @lpicturename,
		payorrelationship1	= @lpayorrelationship1,
		payorrelationship2	= @lpayorrelationship2
	WHERE applicationcode = @lapplicationcode

	SELECT @lapplicationcode AS applicationcode, @lapplicationno AS applicationno
END



GO

-- ---- sp_saveasoaccountfund ----
CREATE PROCEDURE [dbo].[sp_saveasoaccountfund] 
	-- Add the parameters for the stored procedure here
	
	@fundno			Int,
	@fundcode		Varchar(50),
	@fundescription	Varchar(100),	
	@userno			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lfundno			Int				= @fundno,
			@lfundcode			Varchar(50)		= @fundcode,
			@lfundescription	Varchar(100)	= @fundescription,	
			@luserno			Int				= @userno

    -- Insert statements for procedure here

	IF @lfundno = NULL OR @lfundno = 0  
        BEGIN  
			INSERT INTO tblasoaccountfunds(dateencoded, encodedby) 
			VALUES(GETDATE(), @luserno) 
			SELECT @lfundno = @@IDENTITY 
        END  

	UPDATE tblasoaccountfunds  
	SET fundcode	= @lfundcode,
		description	= @lfundescription
	WHERE fundno = @lfundno   
	OPTION(RECOMPILE)

	SELECT @lfundno AS fundno

END
GO

-- ---- sp_saveauthoritytodeductsettingsv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveauthoritytodeductsettingsv2]
	-- Add the parameters for the stored procedure here
	@detno				Int,
	@compcode			Int,
	@title				Varchar(200),
	@body				Varchar(MAX),
	@confirmationtext	Varchar(500),
	@userno				Int,
	@atdtext			Varchar(500)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@ldetno				Int				= @detno,
			@lcompcode			Int				= @compcode,
			@ltitle				Varchar(200)	= @title,
			@lbody				Varchar(MAX)	= @body,
			@lconfirmationtext	Varchar(500)	= @confirmationtext,
			@luserno			Int				= @userno,
			@latdtext			Varchar(500)	= @atdtext

    -- Insert statements for procedure here
		IF @ldetno = NULL OR @ldetno = 0
			BEGIN
				INSERT INTO tblauthoritytodeductsettings (datecreated, createdby, compcode) VALUES (GETDATE(), @luserno, @lcompcode)
				SELECT @ldetno = @@IDENTITY
			END

		UPDATE tblauthoritytodeductsettings
		SET title		 	 = @ltitle,
			body			 = @lbody,
			confirmationtext = @lconfirmationtext,
			atdtext			 = @latdtext
		WHERE detno = @ldetno
		OPTION(RECOMPILE)

		SELECT @ldetno AS detno
END
GO

-- ---- sp_saveautorenewal ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveautorenewal]
	-- Add the parameters for the stored procedure here
	@contractcode	INT,
	@encodedby		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	DECLARE @lcontractcode	INT				= @contractcode,
			@lencodedby		INT				= @encodedby,
			@lportalcode	INT				= 0,
			@lportalno		VARCHAR(100)	= '',
			@lautorenewal	VARCHAR(50)		= (SELECT NEWID())
	
	IF EXISTS (
		SELECT 1
		FROM tblcompanycontractyears a
		INNER JOIN tblmembers b ON a.compcode = b.compcode AND b.statuscode IN (1, 2, 6) AND b.expiry = DATEADD(DAY, -1, a.effectivity) AND b.classorder = 0
		WHERE contractcode = @lcontractcode
	)
	BEGIN
		INSERT INTO tblportalupload (compcode, contractcode, uploadtype, statuscode, datetransferred, datequeued, dateencoded, encodedby, seekby, enrollmentperiodfrom, enrollmentperiodto, enrollmentperiodsamewithaccount, autorenewal)
		SELECT compcode, contractcode, 'NR-PD', 3, GETDATE(), GETDATE(), GETDATE(), @lencodedby, 1, effectivity, expiry, 1, @lautorenewal
		FROM tblcompanycontractyears
		WHERE contractcode = @lcontractcode

		SET @lportalcode = SCOPE_IDENTITY()

		SET @lportalno = FORMAT(GETDATE(),'yyyyMMdd') + RIGHT('0000' + CAST(@lportalcode AS VARCHAR(20)), CASE WHEN LEN(@lportalcode) <= 4 THEN 4 ELSE LEN(@lportalcode) END)

		UPDATE tblportalupload
		SET portalno = @lportalno,
			importedcodedummy = @lportalno
		WHERE portalcode = @lportalcode
	END
	
	IF EXISTS (
		SELECT 1
		FROM tblcompanycontractyears a
		INNER JOIN tblmembers b ON a.compcode = b.compcode AND b.statuscode IN (1, 2, 6) AND b.expiry = DATEADD(DAY, -1, a.effectivity) AND b.classorder = 1 AND b.principalcode = 0
		WHERE contractcode = @lcontractcode
	)
	BEGIN
		INSERT INTO tblportalupload (compcode, contractcode, uploadtype, statuscode, datetransferred, datequeued, dateencoded, encodedby, seekby, enrollmentperiodfrom, enrollmentperiodto, enrollmentperiodsamewithaccount, autorenewal)
		SELECT compcode, contractcode, 'NR-D', 3, GETDATE(), GETDATE(), GETDATE(), @lencodedby, 1, effectivity, expiry, 1, @lautorenewal
		FROM tblcompanycontractyears
		WHERE contractcode = @lcontractcode

		SET @lportalcode = SCOPE_IDENTITY()

		SET @lportalno = FORMAT(GETDATE(),'yyyyMMdd') + RIGHT('0000' + CAST(@lportalcode AS VARCHAR(20)), CASE WHEN LEN(@lportalcode) <= 4 THEN 4 ELSE LEN(@lportalcode) END)

		UPDATE tblportalupload
		SET portalno = @lportalno,
			importedcodedummy = @lportalno
		WHERE portalcode = @lportalcode
	END
	
	IF EXISTS (
		SELECT 1
		FROM tblcompanycontractyears a
		INNER JOIN tblmembers b ON a.compcode = b.compcode AND b.statuscode IN (1, 2, 6) AND b.expiry = DATEADD(DAY, -1, a.effectivity) AND b.classorder = 1 AND b.principalcode <> 0
		INNER JOIN tblmembers c ON b.principalcode = c.membercode AND b.compcode <> c.compcode
		LEFT JOIN tblmemberamendment d ON c.compcode = d.compcode AND c.membercode = d.membercode AND d.amendmenttype = 17 AND d.statuscode <> 3
		WHERE a.contractcode = @lcontractcode AND a.effectivity IN (c.effectivity, CAST(ISNULL(d.newvalue, '1/1/1900') AS DATE))
	)
	BEGIN
		INSERT INTO tblportalupload (compcode, contractcode, uploadtype, statuscode, datetransferred, datequeued, dateencoded, encodedby, seekby, enrollmentperiodfrom, enrollmentperiodto, enrollmentperiodsamewithaccount, autorenewal)
		SELECT compcode, contractcode, 'NR-DOP', 3, GETDATE(), GETDATE(), GETDATE(), @lencodedby, 1, effectivity, expiry, 1, @lautorenewal
		FROM tblcompanycontractyears
		WHERE contractcode = @lcontractcode

		SET @lportalcode = SCOPE_IDENTITY()

		SET @lportalno = FORMAT(GETDATE(),'yyyyMMdd') + RIGHT('0000' + CAST(@lportalcode AS VARCHAR(20)), CASE WHEN LEN(@lportalcode) <= 4 THEN 4 ELSE LEN(@lportalcode) END)

		UPDATE tblportalupload
		SET portalno = @lportalno,
			importedcodedummy = @lportalno
		WHERE portalcode = @lportalcode
	END

	UPDATE tblcompanycontractyears
	SET autorenewal = @lautorenewal
	WHERE contractcode = @lcontractcode

END
GO

-- ---- sp_savebatchapejournal ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_savebatchapejournal] 
	-- Add the parameters for the stored procedure here
	
	@detno			Int,
	@batchcode		Int,
	@description	Varchar(240),
	@userno			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@ldetno				Int				= @detno,
			@lbatchcode			Int				= @batchcode,
			@ldescription		Varchar(200)	= @description,
			@luserno			Int				= @userno

    -- Insert statements for procedure here

	IF @ldetno = NULL OR @ldetno = 0  
        BEGIN  
			INSERT INTO tblbatchapejournal(batchcode, encodedby, dateencoded) 
			VALUES(@lbatchcode, @luserno, GETDATE()) 
			SELECT @ldetno = @@IDENTITY 
        END  

	UPDATE tblbatchapejournal  
	SET description	= @ldescription
	WHERE detno = @ldetno   
	OPTION(RECOMPILE)

	SELECT @ldetno AS detno

END
GO

-- ---- sp_savebatcholdmemberfeesv2 ----
CREATE   PROCEDURE [dbo].[sp_savebatcholdmemberfeesv2]
	-- Add the parameters for the stored procedure here
	
	@batchcode Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	DECLARE @lbatchcode			Int				= @batchcode

    -- Insert statements for procedure here.

	UPDATE a SET
	active = 0,
	batchcode = 0,
	cancelled = 1
	FROM tblmemberfees a WITH(NOLOCK)
	INNER JOIN
	(
		SELECT DISTINCT b.membercode 
		FROM tblmemberuploaddetails b WITH(NOLOCK) 
		WHERE b.batchcode = @lbatchcode
		
	) b 
	ON a.membercode = b.membercode
	WHERE active <> 0 OR batchcode <> 0 OR cancelled <> 1 --no op filter
	OPTION(RECOMPILE)

END
GO

-- ---- sp_saveclaimreimrequirements ----
CREATE   PROCEDURE [dbo].[sp_saveclaimreimrequirements]
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@billcode			Int,
	@requirementcode	Int,
	@remarks			Varchar(100),
	@postedby			Int,
	@dateposted			Smalldatetime

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @ldetno				Int				= @detno,
			@lbillcode			Int				= @billcode,
			@lrequirementcode	Int				= @requirementcode,
			@lremarks			Varchar(100)	= @remarks,
			@lpostedby			Int				= @postedby,
			@ldateposted		Smalldatetime	= @dateposted

	IF (@ldetno = 0 OR @ldetno = NULL)
		BEGIN
			INSERT INTO tblclaimreimrequirements (billcode, requirementcode, postedby)
			VALUES (@lbillcode, @lrequirementcode, @lpostedby)
			SELECT @ldetno = @@IDENTITY
		END

	UPDATE tblclaimreimrequirements
	SET remarks = @lremarks,
		dateposted = @ldateposted
	WHERE detno = @ldetno 
	OPTION(RECOMPILE)

	SELECT @ldetno AS detno
END
GO

-- ---- sp_saveclaimsuploadbatchv3 ----
CREATE PROCEDURE [dbo].[sp_saveclaimsuploadbatchv3] --506, 5, 5014, 2785, 0, 0, 0, 'N-PD', '5522_6912_05.20.001 new.xlsx', 4, 0, '202005200506', '', 1
	-- Add the parameters for the stored procedure here
	
	@batchcode			Int,
	@uploadedby			Int,
	@filename			Varchar(100),
	@requiredfields		Varchar(100),
	@uploadtype			Int,
	@adjudication		Tinyint

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lbatchcode		 Int			 = @batchcode,
			@luploadedby	 Int			 = @uploadedby,
			@lfilename		 Varchar(100)	 = @filename,
			@lrequiredfields Varchar(100)    = @requiredfields,
			@luploadtype	 Int			 = @uploadtype,
			@ladjudication	 Tinyint		 = @adjudication,
			@lbatchno		 Varchar(20)     = ''
			

    -- Insert statements for procedure here.
	IF @lbatchcode = NULL OR @lbatchcode = 0
		BEGIN
			INSERT INTO tbluploadbatchclaims (uploadedby, dateuploaded)
			VALUES (@luploadedby, GETDATE())
			SELECT @lbatchcode = @@IDENTITY

			SET @lbatchno = FORMAT(GETDATE(),'yyyyMMdd') + RIGHT('0000' + CAST(@lbatchcode AS VARCHAR(20)), CASE WHEN LEN(@lbatchcode) <= 4 THEN 4 ELSE LEN(@lbatchcode) END)
		END
	
	UPDATE tbluploadbatchclaims
		SET statuscode = 1,
			batchno = @lbatchno,
			filename = @lfilename,
			requiredfields = @lrequiredfields,
			uploadtype = @luploadtype,
			adjudication = @ladjudication
	WHERE batchcode = @lbatchcode

	SELECT @lbatchcode as batchcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_savecptv2 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_savecptv2]
	@cptno				Int,
	@cptcode			Varchar(20),
	@cptsymbol			Varchar(100),
	@cptsection			Int,
	@cptsubsection		Int,
	@cptdefinition		Varchar(max),
	@meddescription		Varchar(240),
	@cptname			Varchar(240),
	@ddl				Bit,
	@display			Bit,
	@withdoctor			Bit,
	@rvsrate			Numeric(18,2),
	@wardrate			Numeric(18,2),
	@suiterate			Numeric(18,2),
	@oprate				Numeric(18,2),
	@icurate			Numeric(18,2),
	@semiprivaterate	Numeric(18,2),
	@privaterate		Numeric(18,2),
	@deluxerate			Numeric(18,2),
	@cptgroup			Int,
	@commonname			Varchar(240),
	@ruvrate			Numeric(18,2)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lcptno				Int				= @cptno,
			@lcptcode			Varchar(20)		= @cptcode,
			@lcptsymbol			Varchar(100)	= @cptsymbol,
			@lcptsection		Int				= @cptsection,
			@lcptsectionname	Varchar(240)	= '',
			@lcptsubsection		Int				= @cptsubsection,
			@lcptsubsectionname	Varchar(240)	= '',
			@lcptdefinition		Varchar(max)	= @cptdefinition,
			@lmeddescription	Varchar(240)	= @meddescription,
			@lcptname			Varchar(240)	= @cptname,
			@lddl				Bit				= @ddl,
			@ldisplay			Bit				= @display,
			@lwithdoctor		Bit				= @withdoctor,
			@lrvsrate			Numeric(18,2)	= @rvsrate,
			@lwardrate			Numeric(18,2)	= @wardrate,
			@lsuiterate			Numeric(18,2)	= @suiterate,
			@loprate			Numeric(18,2)	= @oprate,
			@licurate			Numeric(18,2)	= @icurate,
			@lsemiprivaterate	Numeric(18,2)	= @semiprivaterate,
			@lprivaterate		Numeric(18,2)	= @privaterate,
			@ldeluxerate		Numeric(18,2)	= @deluxerate,
			@lcptgroup			Int				= @cptgroup,
			@lcommonname		Varchar(240)	= @commonname,
			@lruvrate			Numeric(18,2)	= @ruvrate

    -- Insert statements for procedure here
		IF @lcptno = NULL OR @lcptno = 0  
            BEGIN  
				INSERT INTO tblcpttable(cptcode, cptsymbol) 
				VALUES(@lcptcode, @lcptsymbol) 
				SELECT @lcptno = @@IDENTITY 
            END  
	
		SELECT @lcptsectionname = LTRIM(RTRIM(description)) FROM tblgentables WHERE tablename = 'CPT SECTION' ORDER BY description
		SELECT @lcptsubsectionname = LTRIM(RTRIM(description)) FROM tblgentables WHERE tablename = 'CPT SUBSECTION' ORDER BY description

		UPDATE tblcpttable  
		SET sectcode			= @lcptsection,
			subsectcode			= @lcptsubsection,
			descriptionlong		= @lcptdefinition,
			descriptionmed		= @lmeddescription,
			descriptionshort	= @lcptname,
			ddl					= @lddl,
			lastupdated			= GETDATE(),
			display				= @ldisplay,
			withdoctor			= @lwithdoctor,
			rvsrate				= @lrvsrate, 
			wardrate			= @lwardrate,
			suiterate			= @lsuiterate,
			icurate				= @licurate,
			semiprivaterate		= @lsemiprivaterate,
			privaterate			= @lprivaterate,
			deluxerate			= @ldeluxerate,
			groupcode			= @lcptgroup,
			cptsection			= @lcptsectionname,
			cptsubsection		= @lcptsubsectionname,
			commonname			= @lcommonname,
			ruvrate				= @lruvrate,
			oprate				= @loprate			
		WHERE cptno = @lcptno 
		OPTION(RECOMPILE)

		SELECT @lcptno AS cptno
END
GO

-- ---- sp_savecredittermextensionsettings ----
CREATE PROCEDURE [dbo].[sp_savecredittermextensionsettings]
	-- Add the parameters for the stored procedure here
	
	@globalcredittermmonthly	Int,
	@globalcredittermquarterly	Int,
	@globalcredittermsemiannual	Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lglobalcredittermmonthly		Int	= @globalcredittermmonthly,
			@lglobalcredittermquarterly		Int	= @globalcredittermquarterly,
			@lglobalcredittermsemiannual	Int	= @globalcredittermsemiannual,
			@ldetno							Int = 1
	
	UPDATE tblsettingsunderwriting
	SET globalcredittermmonthly = @lglobalcredittermmonthly,
		globalcredittermquarterly = @lglobalcredittermquarterly,
		globalcredittermsemiannual = @lglobalcredittermsemiannual
	OPTION(RECOMPILE)
		

	SELECT @ldetno AS detno
END
GO

-- ---- sp_savedcftemplates ----
CREATE PROCEDURE [dbo].[sp_savedcftemplates]
	-- Add the parameters for the stored procedure here
	@detno				Int,
	@templatecode		Varchar(20),
	@templatename		Varchar(100),
	@encodedby			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @ldetno				Int				= @detno,
			@ltemplatecode		Varchar(20)		= @templatecode,
			@ltemplatename		Varchar(100)	= @templatename,
			@lencodedby			Int				= @encodedby

	IF (@ldetno = 0 OR @ldetno = NULL)
		BEGIN
			INSERT INTO tbldcftemplates(encodedby, dateencoded)
			VALUES (@lencodedby, GETDATE())
			SELECT @ldetno = @@IDENTITY
		END

	UPDATE tbldcftemplates
	SET templatecode	= @ltemplatecode,
		templatename	= @ltemplatename
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	SELECT @ldetno AS detno

END
GO

-- ---- sp_savedoctorewtjournal ----
CREATE PROCEDURE [dbo].[sp_savedoctorewtjournal] 
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@ewtdetailsdetno	Int,
	@description		Varchar(MAX),
	@userno				Int


AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lewtdetailsdetno	Int				= @ewtdetailsdetno,
			@ldescription		Varchar(MAX)	= @description,
			@luserno			Int				= @userno,
			@ldetno				Int				= @detno

    -- Insert statements for procedure here
	
	IF @ldetno = 0 OR @ldetno = NULL
		BEGIN
			INSERT INTO tbldoctorewtjournal(ewtdetaildetno, datecreated, userno)
			VALUES(@lewtdetailsdetno, GETDATE(), @luserno)
			SELECT @ldetno = @@IDENTITY 
		END	
	
	UPDATE tbldoctorewtjournal
	SET description = @ldescription
	WHERE detno = @ldetno
	OPTION(RECOMPILE)
	
	SELECT @ldetno AS detno
	

END
GO

-- ---- sp_savefranchiseuserauditlevel ----
CREATE PROCEDURE [dbo].[sp_savefranchiseuserauditlevel] 

	@detno		Int,
	@recordcode	Int,
	@userno		Int,
	@encodedby	Int

AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ldetno			Int	= @detno,
			@lrecordcode	Int	= @recordcode,
			@luserno		Int	= @userno,
			@lencodedby		Int	= @encodedby

	IF @ldetno = 0 OR @ldetno = NULL	
		BEGIN
			INSERT INTO tblfranchiseuserauditlevel( recordcode, dateencoded, encodedby) 
			VALUES(@lrecordcode, GETDATE(), @lencodedby)
			SELECT @ldetno = @@IDENTITY
		END
	
	UPDATE tblfranchiseuserauditlevel
	SET userno = @luserno
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	SELECT @luserno AS userno

END
GO

-- ---- sp_savememberportalamendmemberbenefitclass ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_savememberportalamendmemberbenefitclass]
	-- Add the parameters for the stored procedure here
	
	@membercode		Int,
	@benefitclass	Varchar(100)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lmembercode		Int				= @membercode,
			@lbenefitclass		Varchar(100)	= @benefitclass

	EXEC sp_opensymmetric
	
	IF @lbenefitclass <> NULL OR @lbenefitclass <> ''
		BEGIN
			UPDATE a
			SET benefitclass = @lbenefitclass,
				premiumclass = d.premiumclasscode
			FROM tblmembers a
			OUTER APPLY (SELECT contractcode FROM tblcompanycontractyears c WITH(NOLOCK) WHERE c.compcode = a.compcode) c
			OUTER APPLY(SELECT compcode, contractcode FROM tblcompanyclasses b WITH(NOLOCK) WHERE b.compcode = a.compcode AND b.contractcode = c.contractcode AND b.classcode = @lbenefitclass) b
			OUTER APPLY(SELECT premiumclasscode FROM tblcompanyclassesbilling d WITH(NOLOCK) WHERE d.compcode = b.compcode AND d.contractcode = b.contractcode AND d.billingschedule = a.billingschedule) d
			WHERE a.membercode = @membercode 
		END

	EXEC sp_closesymmetric

END






GO

-- ---- sp_savememberportalsettingsv4 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE       PROCEDURE [dbo].[sp_savememberportalsettingsv4]
	-- Add the parameters for the stored procedure here
	@detno					Int,
	@compcode				Int,
	@showpremiuminfo		Bit,
	@showcivilstatus		Bit,
	@principaltopup			Bit,
	@independentcpd			Bit,
	@companyemployeeshare	Bit,
	@dependentcoveragetype	Bit,
	@topupcoverage			Bit,
	@homogendependenttopup	BIT,
	@dependenttopup			BIT,
	@showconfirm			BIT,
	@userno					Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@ldetno						Int	= @detno,
			@lcompcode					Int	= @compcode,
			@lshowpremiuminfo			Bit	= @showpremiuminfo,
			@lshowcivilstatus			Bit	= @showcivilstatus,
			@lprincipaltopup			Bit = @principaltopup,
			@lindependentcpd			Bit = @independentcpd,
			@lcompanyemployeeshare		Bit = @companyemployeeshare,
			@ldependentcoveragetype		Bit = @dependentcoveragetype,
			@ltopupcoverage				Bit = @topupcoverage,
			@lhomogendependenttopup		BIT = @homogendependenttopup,
			@ldependenttopup			BIT = @dependenttopup,
			@lshowconfirm				BIT = @showconfirm,
			@luserno					Int	= @userno

    -- Insert statements for procedure here
		IF @ldetno = NULL OR @ldetno = 0
			BEGIN
				INSERT INTO tblmemberportalsettings (datecreated, createdby, compcode) VALUES (GETDATE(), @luserno, @lcompcode)
				SELECT @ldetno = @@IDENTITY
			END

		UPDATE tblmemberportalsettings
		SET showpremiuminfo			= @lshowpremiuminfo,
			showcivilstatus			= @lshowcivilstatus,
			homogendependenttopup	= @lhomogendependenttopup,
			principaltopup			= @lprincipaltopup,
			independentcpd			= @lindependentcpd,
			companyemployeeshare	= @lcompanyemployeeshare,
			dependentcoveragetype	= @ldependentcoveragetype,
			topupcoverage			= @ltopupcoverage,
			showconfirm				= @lshowconfirm,
			dependenttopup			= @ldependenttopup
		WHERE detno = @ldetno
		OPTION(RECOMPILE)

		SELECT @ldetno AS detno
END
GO

-- ---- sp_saveportalreportrequestv2 ----
CREATE   PROCEDURE [dbo].[sp_saveportalreportrequestv2] 
	-- Add the parameters for the stored procedure here
	@requesttype	Varchar(20),
	@requestsource	Int,
	@batchno	Varchar(100),
	@requestedby	Int,
	@dateasof		smalldatetime
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	DECLARE	@lrequesttype	Varchar(20)		= @requesttype,
			@lrequestsource	Int				= @requestsource,
			@lbatchno	Varchar(100)		= @batchno,
			@lrequestedby	Int				= @requestedby,
			@ldateasof		smalldatetime	= @dateasof
    -- Insert statements for procedure here
	INSERT INTO tblportalreportrequest (requesttype, requestsource,batchno, statuscode, progress, filename, daterequested, requestedby, datefrom, dateto, retail)
	VALUES (@lrequesttype, @lrequestsource,@lbatchno, 1, 0, '', GETDATE(), @lrequestedby, '1900-01-01', @ldateasof, 0)
END
GO

-- ---- sp_saveproductlinesv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_saveproductlinesv2]
	-- Add the parameters for the stored procedure here
	
	@productcode		Int,
	@productlinecode	Varchar(20),
	@productline		Varchar(100),
	@required			Bit,
	@createdby			Int,
	@memberportalassoc	Bit,
	@iorta				Bit

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lproductcode		Int				= @productcode,
			@lproductlinecode	Varchar(20)		= @productlinecode,
			@lproductline		Varchar(100)	= @productline,
			@lrequired			Bit				= @required,
			@lcreatedby			Int				= @createdby,
			@lmemberportalassoc	Bit				= @memberportalassoc,
			@liorta				Bit				= @iorta



	IF (@lproductcode = 0 OR @lproductcode = NULL)
		BEGIN
			INSERT INTO tblproductlines (required, createdby, datecreated)
			VALUES (@lrequired, @lcreatedby, GETDATE())
			SELECT @lproductcode = @@IDENTITY
		END

	UPDATE tblproductlines
	SET productlinecode	= @lproductlinecode,
		productline		= @lproductline,
		memberportalassociation = @lmemberportalassoc,
		iorta			= @liorta
	WHERE productcode = @lproductcode
	OPTION(RECOMPILE)

	SELECT @lproductcode AS productcode

END
GO

-- ---- sp_savereimbursementrequirements ----
CREATE PROCEDURE [dbo].[sp_savereimbursementrequirements] 
	-- Add the parameters for the stored procedure here
	
	@detno			 Int,
	@requirementtype Varchar(100),
	@encodedby		 Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @ldetno				Int				= @detno,
			@lrequirementtype	Varchar(100)	= @requirementtype,
			@lencodedby			Int				= @encodedby

	IF @ldetno = 0 OR @ldetno = NULL
		BEGIN
			INSERT INTO tblgentables(tablename, createdby, datecreated)
			VALUES('REIMBURSEMENT REQUIREMENTS', @lencodedby, GETDATE())
			SELECT @ldetno = @@IDENTITY
		END

	UPDATE tblgentables 
	SET description	= @lrequirementtype
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	SELECT @ldetno AS detno

END
GO

-- ---- sp_saveretailfranchisingapprovemedical ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_saveretailfranchisingapprovemedical]
	-- Add the parameters for the stored procedure here
	@franchisecode		Int,
	@applicationcode	Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lfranchisecode		Int			= @franchisecode,
			@lapplicationcode	Int			= @applicationcode,
			@lagentcode			Varchar(20)	= ''

	SET @lagentcode = SUBSTRING(CAST(YEAR(GETDATE()) AS VARCHAR(4)),3,2) + RIGHT('00'+SUBSTRING(CAST(MONTH(GETDATE()) AS VARCHAR(2)),1,2),2) + '-'+ RIGHT('00000'+LTRIM(RTRIM(CAST(@lapplicationcode AS VARCHAR))), 5)

	UPDATE a
	SET agentcode = @lagentcode,
		franchisecode = 0
	FROM tblagents a WITH(NOLOCK)
	WHERE a.franchisecode = @lfranchisecode
	OPTION(RECOMPILE)

	UPDATE a
	SET applicationcode = @lapplicationcode
	FROM tblapplicationjournals a WITH(NOLOCK)
	WHERE a.franchisecode = @lfranchisecode
	OPTION(RECOMPILE)

	UPDATE a
	SET applicationcode = @lapplicationcode
	FROM tblapplicationmedhistory a WITH(NOLOCK)
	WHERE a.franchisecode = @lfranchisecode
	OPTION(RECOMPILE)

	UPDATE a
	SET applicationcode = @lapplicationcode
	FROM tblapplicationprevillnesses a WITH(NOLOCK)
	WHERE a.franchisecode = @lfranchisecode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_saveretailfranchisingjournal ----
CREATE PROCEDURE [dbo].[sp_saveretailfranchisingjournal] 
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@franchisecode		Int,
	@description		Varchar(MAX),
	@encodedby			Int


AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldetno				Int				= @detno,
			@lfranchisecode		Int				= @franchisecode,
			@ldescription		Varchar(MAX)	= @description,
			@lencodedby			Int				= @encodedby
			

    -- Insert statements for procedure here
	
	IF @ldetno = 0 OR @ldetno = NULL
		BEGIN
			INSERT INTO tblapplicationjournals(franchisecode, dateencoded, encodedby, required)
			VALUES(@lfranchisecode, GETDATE(), @lencodedby, 1)
			SELECT @ldetno = @@IDENTITY 
		END	
	
	UPDATE a
	SET description = @ldescription
	FROM tblapplicationjournals a WITH(NOLOCK)
	WHERE detno = @ldetno
	OPTION(RECOMPILE)
	
	SELECT @ldetno AS detno
	

END
GO

-- ---- sp_saveretailfranchisingmedhistory ----
CREATE PROCEDURE [dbo].[sp_saveretailfranchisingmedhistory]
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@franchisecode		Int,
	@relationship		Varchar(20),
	@medicalhistory		Varchar(100),
	@agerange1			Varchar(20),
	@healthstate		Varchar(50),
	@agerange2			Varchar(20),
	@causeofdeath		Varchar(50)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldetno				Int				= @detno,
			@lfranchisecode		Int				= @franchisecode,
			@lrelationship		Varchar(20)		= @relationship,
			@lmedicalhistory	Varchar(100)	= @medicalhistory,
			@lagerange1			Varchar(20)		= @agerange1,
			@lhealthstate		Varchar(50)		= @healthstate,
			@lagerange2			Varchar(20)		= @agerange2,
			@lcauseofdeath		Varchar(50)		= @causeofdeath
		
	IF @ldetno = NULL OR @ldetno = 0  
        BEGIN  
			INSERT INTO tblapplicationmedhistory(franchisecode) 
			VALUES(@lfranchisecode) 
			SELECT @ldetno = @@IDENTITY 
        END  	
	
	UPDATE a
	SET relationship = @lrelationship,
		medicalhistory = @lmedicalhistory,
		agerange1 = @lagerange1,
		healthstate = @lhealthstate,
		agerange2 = @lagerange2,
		causeofdeath  = @lcauseofdeath
	FROM tblapplicationmedhistory a WITH(NOLOCK)
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	SELECT @ldetno AS detno
END
GO

-- ---- sp_saveretailfranchisingpayor ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_saveretailfranchisingpayor] --'', '', '', '', '', '', 0, 0, 99, '', '', 1, 0

	@agentno				Int,
	@franchisecode			Int,
	@organization			Bit,
	@agenttype				Int,
	@agentname				Varchar(100),
	@telephone				Varchar(20),
	@fax					Varchar(20),
	@mobile					Varchar(20),
	@tinno					Varchar(20),
	@streetaddress			Varchar(100),
	@citycode				Int,
	@provincecode			Int,
	@zipcode				Varchar(10),
	@encodedby				Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
			
	DECLARE @lagentno				Int				= @agentno,
			@lfranchisecode			Int				= @franchisecode,
			@lorganization			Bit				= @organization,
			@lagenttype				Varchar(50)		= @agenttype,
			@lagentname				Varchar(100)	= @agentname,
			@ltelephone				Varchar(20)		= @telephone,
			@lfax					Varchar(20)		= @fax,
			@lmobile				Varchar(20)		= @mobile,
			@ltinno					Varchar(20)		= @tinno,
			@lstreetaddress			Varchar(100)	= @streetaddress,
			@lcitycode				Int				= @citycode,
			@lprovincecode			Int				= @provincecode,
			@lzipcode				Varchar(10)		= @zipcode,
			@lencodedby				Int				= @encodedby,
			@lagentcode 			Varchar(20)		= ''

	IF @lagentno = 0 OR @lagentno = null
		BEGIN
			INSERT INTO tblagents(dateencoded, encodedby) VALUES(GETDATE(), @lencodedby)
			SELECT @lagentno = @@IDENTITY 
		END

		SET @lagentcode = SUBSTRING(CAST(YEAR(GETDATE()) AS VARCHAR(4)),3,2) + RIGHT('00'+SUBSTRING(CAST(MONTH(GETDATE()) AS VARCHAR(2)),1,2),2) + '-'+ RIGHT('00000'+LTRIM(RTRIM(CAST(@lfranchisecode AS VARCHAR))), 5)

	UPDATE tblagents
	SET agentcode = @lagentcode,
		organization = @lorganization,
		agenttype = @lagenttype,
		agentname = @lagentname,
		telephone = @ltelephone,
		mobile = @lmobile,
		fax = @lfax,
		tinno = @ltinno,
		streetaddress = @lstreetaddress,
		citycode = @lcitycode,
		provincecode = @lprovincecode,
		zipcode = @lzipcode,
		franchisecode = @lfranchisecode
	WHERE agentno = @lagentno

	SELECT @lagentno AS agentno
END



GO

-- ---- sp_saveretailfranchisingprevillnesses ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_saveretailfranchisingprevillnesses]
	-- Add the parameters for the stored procedure here
	
	@detno				Int,
	@franchisecode		Int,
	@membercode			Int,
	@medicalitem		Smallint,
	@medicalanswer		Bit,
	@diagnosis			Varchar(100),
	@icdno				Smallint,
	@treatmentdate		Smalldatetime,
	@treatmentcourse	Varchar(80),
	@doctorname			Varchar(80),
	@hospitalname		Varchar(80),
	@surgery			Bit

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ldetno				Int				= @detno,
			@lfranchisecode		Int				= @franchisecode,
			@lmembercode		Int				= @membercode,
			@lmedicalitem		Smallint		= @medicalitem,
			@lmedicalanswer		Bit				= @medicalanswer,
			@ldiagnosis			Varchar(100)	= @diagnosis,
			@licdno				Smallint		= @icdno,
			@ltreatmentdate		Smalldatetime	= @treatmentdate,
			@ltreatmentcourse	Varchar(80)		= @treatmentcourse,
			@ldoctorname		Varchar(80)		= @doctorname,
			@lhospitalname		Varchar(80)		= @hospitalname,
			@lsurgery			Bit				= @surgery
		
	IF @ldetno = NULL OR @ldetno = 0  
        BEGIN  
			INSERT INTO tblapplicationprevillnesses(franchisecode) 
			VALUES(@lfranchisecode) 
			SELECT @ldetno = @@IDENTITY 
        END  	
	
	UPDATE a
	SET membercode = @lmembercode,
		medicalitem = @lmedicalitem, 
		medicalanswer = @lmedicalanswer, 
		icdno = @licdno, 
		treatmentdate = @ltreatmentdate, 
		treatmentcourse = @ltreatmentcourse, 
		surgery = @lsurgery,
		diagnosis = @ldiagnosis,
		hospitalname = @lhospitalname,
		doctorname = @ldoctorname
	FROM tblapplicationprevillnesses a WITH(NOLOCK)
	WHERE detno = @ldetno
	OPTION(RECOMPILE)

	SELECT @ldetno AS detno
END
GO

-- ---- sp_savesav2 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_savesav2]
	-- Add the parameters for the stored procedure here
	@sacode			Int,
	@categcode		Int,
	@benefitcode	Varchar(50),
	@description	Varchar(200),
	@remarks		Varchar(200),
	@rider			Bit,
	@display		Bit,
	@iorta			Bit,
	@userno			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lsacode		Int				= @sacode,
			@lcategcode		Int				= @categcode,
			@lbenefitcode	Varchar(50)		= @benefitcode,
			@ldescription	Varchar(200)	= @description,
			@lremarks		Varchar(200)	= @remarks,
			@lrider			Bit				= @rider,
			@ldisplay		Bit				= @display,
			@luserno		Int				= @userno,
			@liorta			Bit				= @iorta,
			@ldetno			Int				= 0

    -- Insert statements for procedure here
		IF @lsacode = NULL OR @lsacode = 0
			BEGIN
				INSERT INTO tblbenefitsa (encodedby, dateencoded) VALUES (@luserno, GETDATE())
				SELECT @lsacode = @@IDENTITY

			END

		SELECT @ldetno = ISNULL(detno, 0) FROM tblgentables WHERE tablename = 'SOB LIMITS' AND recordno = 5 AND detno = @lcategcode
		OPTION(RECOMPILE)

		UPDATE tblbenefitsa
		SET categcode	= @lcategcode,
			description	= @ldescription,
			benefitcode = @lbenefitcode,
			remarks		= @lremarks,
			rider		= @lrider,
			display		= @ldisplay,
			iorta		= @liorta,
			excluded	= Iif(@ldetno <> 0, 1, 0)
		WHERE sacode = @lsacode
		OPTION(RECOMPILE)

		SELECT @lsacode AS sacode
END
GO

-- ---- sp_savesav3 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_savesav3]
	-- Add the parameters for the stored procedure here
	@sacode			Int,
	@categcode		Int,
	@benefitcode	Varchar(50),
	@description	Varchar(200),
	@remarks		Varchar(200),
	@rider			Bit,
	@display		Bit,
	@iorta			Bit,
	@dentalcoverage Tinyint,
	@userno			Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lsacode		Int				= @sacode,
			@lcategcode		Int				= @categcode,
			@lbenefitcode	Varchar(50)		= @benefitcode,
			@ldescription	Varchar(200)	= @description,
			@lremarks		Varchar(200)	= @remarks,
			@lrider			Bit				= @rider,
			@ldisplay		Bit				= @display,
			@luserno		Int				= @userno,
			@liorta			Bit				= @iorta,
			@ldentalcoverage Tinyint		= @dentalcoverage,
			@ldetno			Int				= 0

    -- Insert statements for procedure here
		IF @lsacode = NULL OR @lsacode = 0
			BEGIN
				INSERT INTO tblbenefitsa (encodedby, dateencoded) VALUES (@luserno, GETDATE())
				SELECT @lsacode = @@IDENTITY

			END

		SELECT @ldetno = ISNULL(detno, 0) FROM tblgentables WHERE tablename = 'SOB LIMITS' AND recordno = 5 AND detno = @lcategcode
		OPTION(RECOMPILE)

		UPDATE tblbenefitsa
		SET categcode	= @lcategcode,
			description	= @ldescription,
			benefitcode = @lbenefitcode,
			remarks		= @lremarks,
			rider		= @lrider,
			display		= @ldisplay,
			iorta		= @liorta,
			dentalcoverage = @ldentalcoverage,
			excluded	= Iif(@ldetno <> 0, 1, 0)
		WHERE sacode = @lsacode
		OPTION(RECOMPILE)

		SELECT @lsacode AS sacode
END
GO

-- ---- sp_searchsalesportalbenefitclass ----
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_searchsalesportalbenefitclass]
	-- Add the parameters for the stored procedure here
	
	@searchkey			Varchar(100),
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lsearchkey			Varchar(100)	= @searchkey,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lnodata			Bit				= 0
	
	IF (@lsearchkey = '')
		BEGIN
			SET @lnodata = 1;
		END

	SELECT @rowcount = COUNT(1)
	FROM tblcompanyclasses a WITH(NOLOCK)	
	OUTER APPLY (SELECT TOP 1 displaysalesportal FROM tblcompanybenefitplan c WHERE a.classcode = c.classcode AND c.displaysalesportal = 1) c
	WHERE (((@lnodata = 1 AND detno = 0) OR (@lnodata = 0 AND detno <> 0))
	AND ((@lsearchkey = '' AND detno <> 0) OR (@lsearchkey <> '' AND classcode LIKE'%'+@lsearchkey+'%' OR classname LIKE'%'+@lsearchkey+'%'))
	AND (templatetype = 2)
	AND (c.displaysalesportal <> 0 OR c.displaysalesportal <> NULL))
	OPTION(RECOMPILE)

	If @pageno <= 0 or @rowctr <= 0
		BEGIN
			SELECT detno,
			classcode = LTRIM(RTRIM(classcode)),
			classname = LTRIM(RTRIM(classname)),
			productline = ISNULL(LTRIM(RTRIM(b.productline)), ''),
			agefrom, ageto, agefromdep, agetodep
			FROM tblcompanyclasses a WITH(NOLOCK)
			OUTER APPLY (SELECT productline FROM tblproductlines b WITH(NOLOCK) WHERE a.productcode = b.productcode) b
			OUTER APPLY (SELECT TOP 1 displaysalesportal FROM tblcompanybenefitplan c WHERE a.classcode = c.classcode AND c.displaysalesportal = 1) c
			WHERE (((@lnodata = 1 AND detno = 0) OR (@lnodata = 0 AND detno <> 0))
			AND ((@lsearchkey = '' AND detno <> 0) OR (@lsearchkey <> '' AND classcode LIKE'%'+@lsearchkey+'%' OR classname LIKE'%'+@lsearchkey+'%'))
			AND (templatetype = 2)
			AND (c.displaysalesportal <> 0 OR c.displaysalesportal <> NULL))
			ORDER BY classcode
		END
	ELSE
		BEGIN
			SELECT detno,
			classcode = LTRIM(RTRIM(classcode)),
			classname = LTRIM(RTRIM(classname)),
			productline = ISNULL(LTRIM(RTRIM(b.productline)), ''),
			agefrom, ageto, agefromdep, agetodep
			FROM tblcompanyclasses a WITH(NOLOCK)
			OUTER APPLY (SELECT productline FROM tblproductlines b WITH(NOLOCK) WHERE a.productcode = b.productcode) b
			OUTER APPLY (SELECT TOP 1 displaysalesportal FROM tblcompanybenefitplan c WHERE a.classcode = c.classcode AND c.displaysalesportal = 1) c
			WHERE (((@lnodata = 1 AND detno = 0) OR (@lnodata = 0 AND detno <> 0))
			AND ((@lsearchkey = '' AND detno <> 0) OR (@lsearchkey <> '' AND classcode LIKE'%'+@lsearchkey+'%' OR classname LIKE'%'+@lsearchkey+'%'))
			AND (templatetype = 2)
			AND (c.displaysalesportal <> 0 OR c.displaysalesportal <> NULL))
			ORDER BY classcode
			OFFSET ((@lpageno - 1) * @lrowctr) ROWS
			FETCH NEXT @lrowctr ROWS ONLY
			OPTION(RECOMPILE)		
		END

	

END
GO

-- ---- sp_searchsalesportalretailbenefitclass ----
CREATE PROCEDURE [dbo].[sp_searchsalesportalretailbenefitclass] 
	-- Add the parameters for the stored procedure here
	
	@searchkey			Varchar(100),
	@productcode		Int,
	@membertype			Varchar(50),
	@roomdetno			Int,
	@effectivity		Smalldatetime,
	@privilegecare		Bit,
	@ageindays			Int,
	@pageno				Int,
	@rowctr				Int,
	@rowcount			Int = 0 OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lsearchkey			Varchar(100)	= @searchkey,
			@lproductcode		Int				= @productcode,
			@lmembertype		Varchar(50)		= @membertype,
			@lroomdetno			Int				= @roomdetno,
			@leffectivity		Smalldatetime	= @effectivity,
			@lprivilegecare		Bit				= @privilegecare,
			@lageindays			Int				= @ageindays,
			@lpageno			Int				= @pageno,
			@lrowctr			Int				= @rowctr,
			@lnodata			Bit				= 0
	
	--IF (@lsearchkey = '')
	--	BEGIN
	--		SET @lnodata = 1;
	--	END

	--IF OBJECT_ID('#count') IS NOT NULL 
	--BEGIN 
	--	DROP TABLE #count
	--END
	
	--CREATE TABLE #count
	--(
	--totalctr int NOT NULL
	--)

	--INSERT INTO #count (totalctr)
	SELECT @rowcount = COUNT(1)
	FROM tblcompanyclasses a WITH(NOLOCK)
	WHERE (((@lnodata = 1 AND a.detno = 0) OR (@lnodata = 0 AND a.detno <> 0))
	AND (a.compcode = 0 AND a.contractcode = 0 AND a.templatetype = 2)
	AND (CAST(@leffectivity AS DATE) BETWEEN CAST(effectivity AS DATE) AND CAST(expiry AS DATE))
	AND ((@lproductcode = 0 AND a.detno <> 0) OR (@lproductcode <> 0 AND a.productcode = @lproductcode))
	AND (@lageindays BETWEEN IIF(a.agefrom < 0, ABS(a.agefrom), a.agefrom * 365) AND IIF(a.ageto < 0, ABS(a.ageto), a.ageto * 365))
	AND LTRIM(TRIM(a.classcode)) IN (
		SELECT LTRIM(TRIM(z.classcode))
		FROM tblcompanybenefitplan z WITH(NOLOCK)
		WHERE z.compcode = 0
		AND z.contractcode = 0
		AND z.displaysalesportal = 1
		AND z.privilegecare = @lprivilegecare
		AND z.approvedby <> 0
	)
	AND ((@lroomdetno = 0 AND a.detno <> 0) OR (@lroomdetno <> 0 AND ((
		SELECT COUNT(1) as reccount
		FROM tblcompanybenefitplan d WITH(NOLOCK)
		WHERE d.compcode = 0
		AND d.contractcode = 0 
		AND d.classcode = a.classcode
		AND ((
			SELECT COUNT(1) as reccount
			FROM tblcompanybenefitlimits e WITH(NOLOCK)
			OUTER APPLY (SELECT sacode, categcode FROM tblbenefitsa f WHERE e.sacode = f.sacode) f
			WHERE e.compcode = 0
			AND d.plancode = e.plancode
			AND f.categcode = 1051
			AND f.sacode = @lroomdetno
		) > 0)
	) > 0)))
	AND ((@lsearchkey = '' AND detno <> 0) OR (@lsearchkey <> '' AND classcode LIKE'%'+@lsearchkey+'%' OR classname LIKE'%'+@lsearchkey+'%')))
	OPTION(RECOMPILE)

	If @pageno <= 0 or @rowctr <= 0
		BEGIN
			SELECT a.detno, a.compcode, a.contractcode,
			a.agefrom, 
			agefromdays = IIF(a.agefrom < 0, ABS(a.agefrom), a.agefrom * 365),
			a.ageto, 
			agetodays = IIF(a.ageto < 0, ABS(a.ageto), a.ageto * 365),
			--a.agefromdep, 
			--agefromdepdays = IIF(a.agefromdep < 0, ABS(a.agefromdep), a.agefromdep * 365),
			--a.agetodep,
			--agetodepdays = IIF(a.agetodep < 0, ABS(a.agetodep), a.agetodep * 365),
			classcode = LTRIM(RTRIM(a.classcode)),
			classname = LTRIM(RTRIM(a.classname)),
			productlinecode = ISNULL(LTRIM(RTRIM(b.productlinecode)), ''),
			productline = ISNULL(LTRIM(RTRIM(b.productline)), '')
			FROM tblcompanyclasses a WITH(NOLOCK)
			OUTER APPLY (SELECT productcode, productlinecode, productline FROM tblproductlines b WITH(NOLOCK) WHERE a.productcode = b.productcode) b
			WHERE (((@lnodata = 1 AND a.detno = 0) OR (@lnodata = 0 AND a.detno <> 0))
			AND (a.compcode = 0 AND a.contractcode = 0 AND a.templatetype = 2)
			AND (CAST(@leffectivity AS DATE) BETWEEN CAST(effectivity AS DATE) AND CAST(expiry AS DATE))
			AND ((@lproductcode = 0 AND a.detno <> 0) OR (@lproductcode <> 0 AND a.productcode = @lproductcode))
			AND (@lageindays BETWEEN IIF(a.agefrom < 0, ABS(a.agefrom), a.agefrom * 365) AND IIF(a.ageto < 0, ABS(a.ageto), a.ageto * 365))
			AND LTRIM(TRIM(a.classcode)) IN (
				SELECT LTRIM(TRIM(z.classcode))
				FROM tblcompanybenefitplan z WITH(NOLOCK)
				WHERE z.compcode = 0
				AND z.contractcode = 0
				AND z.displaysalesportal = 1
				AND z.privilegecare = @lprivilegecare
				AND z.approvedby <> 0
			)
			AND ((@lroomdetno = 0 AND a.detno <> 0) OR (@lroomdetno <> 0 AND ((
				SELECT COUNT(1) as reccount
				FROM tblcompanybenefitplan d WITH(NOLOCK)
				WHERE d.compcode = 0
				AND d.contractcode = 0 
				AND d.classcode = a.classcode
				AND ((
					SELECT COUNT(1) as reccount
					FROM tblcompanybenefitlimits e WITH(NOLOCK)
					OUTER APPLY (SELECT sacode, categcode FROM tblbenefitsa f WHERE e.sacode = f.sacode) f
					WHERE e.compcode = 0
					AND d.plancode = e.plancode
					AND f.categcode = 1051
					AND f.sacode = @lroomdetno
				) > 0)
			) > 0)))
			AND ((@lsearchkey = '' AND detno <> 0) OR (@lsearchkey <> '' AND classcode LIKE'%'+@lsearchkey+'%' OR classname LIKE'%'+@lsearchkey+'%')))
			ORDER BY classcode
		END
	ELSE
		BEGIN
			SELECT a.detno, a.compcode, a.contractcode,
			a.agefrom, 
			agefromdays = IIF(a.agefrom < 0, ABS(a.agefrom), a.agefrom * 365),
			a.ageto, 
			agetodays = IIF(a.ageto < 0, ABS(a.ageto), a.ageto * 365),
			--a.agefromdep, 
			--agefromdepdays = IIF(a.agefromdep < 0, ABS(a.agefromdep), a.agefromdep * 365),
			--a.agetodep,
			--agetodepdays = IIF(a.agetodep < 0, ABS(a.agetodep), a.agetodep * 365),
			classcode = LTRIM(RTRIM(a.classcode)),
			classname = LTRIM(RTRIM(a.classname)),
			productlinecode = ISNULL(LTRIM(RTRIM(b.productlinecode)), ''),
			productline = ISNULL(LTRIM(RTRIM(b.productline)), '')
			FROM tblcompanyclasses a WITH(NOLOCK)
			OUTER APPLY (SELECT productcode, productlinecode, productline FROM tblproductlines b WITH(NOLOCK) WHERE a.productcode = b.productcode) b
			WHERE (((@lnodata = 1 AND a.detno = 0) OR (@lnodata = 0 AND a.detno <> 0))
			AND (a.compcode = 0 AND a.contractcode = 0 AND a.templatetype = 2)
			AND (CAST(@leffectivity AS DATE) BETWEEN CAST(effectivity AS DATE) AND CAST(expiry AS DATE))
			AND ((@lproductcode = 0 AND a.detno <> 0) OR (@lproductcode <> 0 AND a.productcode = @lproductcode))
			AND (@lageindays BETWEEN IIF(a.agefrom < 0, ABS(a.agefrom), a.agefrom * 365) AND IIF(a.ageto < 0, ABS(a.ageto), a.ageto * 365))
			AND LTRIM(TRIM(a.classcode)) IN (
				SELECT LTRIM(TRIM(z.classcode))
				FROM tblcompanybenefitplan z WITH(NOLOCK)
				WHERE z.compcode = 0
				AND z.contractcode = 0
				AND z.displaysalesportal = 1
				AND z.privilegecare = @lprivilegecare
				AND z.approvedby <> 0
			)
			AND ((@lroomdetno = 0 AND a.detno <> 0) OR (@lroomdetno <> 0 AND ((
				SELECT COUNT(1) as reccount
				FROM tblcompanybenefitplan d WITH(NOLOCK)
				WHERE d.compcode = 0
				AND d.contractcode = 0 
				AND d.classcode = a.classcode
				AND ((
					SELECT COUNT(1) as reccount
					FROM tblcompanybenefitlimits e WITH(NOLOCK)
					OUTER APPLY (SELECT sacode, categcode FROM tblbenefitsa f WHERE e.sacode = f.sacode) f
					WHERE e.compcode = 0
					AND d.plancode = e.plancode
					AND f.categcode = 1051
					AND f.sacode = @lroomdetno
				) > 0)
			) > 0)))
			AND ((@lsearchkey = '' AND detno <> 0) OR (@lsearchkey <> '' AND classcode LIKE'%'+@lsearchkey+'%' OR classname LIKE'%'+@lsearchkey+'%')))
			ORDER BY classcode
			OFFSET ((@lpageno - 1) * @lrowctr) ROWS
			FETCH NEXT @lrowctr ROWS ONLY
			OPTION(RECOMPILE)		
		END

	

END
GO

-- ---- sp_updateaccountregistrationv5 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_updateaccountregistrationv5] --'', '', '', '', '', '', 0, 0, 99, '', '', 1, 0

	@compcode					Int,
	@companyname				Varchar(100),
	@premiumcaption				Varchar(100),
	@roundingoff				Smallint,
	@memberpremium				Smallint,
	@vattype					Tinyint,
	@cwtax						Numeric(6,2),
	@restrictmobile				Bit,
	@cppaccount					Bit,
	@asoadminfeetype			Tinyint,
	@asoadminfee				Numeric(18,2),
	@asoservicefeetype			Tinyint,
	@asoservicefee				Numeric(18,2),
	@accounttype				Int,
	@allowmemberportal			Bit,
	@telemedicine				Bit,
	@memberportalaccessfrom		Smalldatetime,
	@memberportalaccessto		Smalldatetime,
	@annivedate					Smalldatetime,
	@wtaxno						Int,
	@wtax						Numeric(6,2),
	@enhancedencryption			Bit,
	@restrictdependentmobile	Bit,
	@maxcpddependent			Tinyint,
	@maxvpddependent			Tinyint
	

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
			
	DECLARE @lcompcode					Int				= @compcode,
			@lcompanyname				Varchar(100)	= @companyname,
			@lpremiumcaption			Varchar(100)	= @premiumcaption,
			@lroundingoff				Smallint		= @roundingoff,
			@lmemberpremium				Smallint		= @memberpremium,
			@lvattype					Tinyint			= @vattype,
			@lcwtax						Numeric(6,2)	= @cwtax,
			@lrestrictmobile			Bit				= @restrictmobile,
			@lcppaccount				Bit				= @cppaccount,
			@lasoadminfeetype			Tinyint			= @asoadminfeetype,
			@lasoadminfee				Numeric(18,2)	= @asoadminfee,
			@lasoservicefeetype			Tinyint			= @asoservicefeetype,
			@lasoservicefee				Numeric(18,2)	= @asoservicefee,
			@laccounttype				Int				= @accounttype,
			@lallowmemberportal			Bit				= @allowmemberportal,
			@ltelemedicine				Bit				= @telemedicine,
			@lmemberportalaccessfrom	Smalldatetime	= @memberportalaccessfrom,
			@lmemberportalaccessto		Smalldatetime	= @memberportalaccessto,
			@lannivedate				Smalldatetime	= @annivedate,
			@lwtaxno					Int				= @wtaxno,
			@lwtax						Numeric(6,2)	= @wtax,
			@lenhancedencryption		Bit				= @enhancedencryption,
			@lrestrictdependentmobile	Bit				= @restrictdependentmobile,
			@lmaxcpddependent			Tinyint			= @maxcpddependent,
			@lmaxvpddependent			Tinyint			= @maxvpddependent

	IF (@lcppaccount = 1)
		BEGIN
			SELECT @laccounttype = detno FROM tblgentables WHERE tablename = 'COMPANY TYPE' AND description = 'COST PLUS PROGRAM (CPP)'
		END
	DECLARE @KeyGUID UNIQUEIDENTIFIER 
	SET @KeyGUID = KEY_GUID('Encrypt')

	EXEC sp_opensymmetric

	UPDATE tblcompany
	SET	companyname				= ENCRYPTBYKEY(@KeyGUID, RTRIM(@lcompanyname)),
		ldflog					= ISNULL(dbo.Decoder(@lcompanyname, 1), ''),
		premiumcaption			= @lpremiumcaption,
		roundingoff				= @lroundingoff,
		memberpremium			= @lmemberpremium,
		vattype					= @lvattype,
		cwtax					= @lcwtax,
		restrictmobile			= @lrestrictmobile,
		companytype				= @laccounttype,
		asoadminfee				= @lasoadminfee,
		asoadminfeetype			= @lasoadminfeetype,
		asoservicefee			= @lasoservicefee,
		asoservicefeetype		= @lasoservicefeetype,
		dateenrolled			= @lannivedate,
		allowmemberportal		= @lallowmemberportal,
		telemedicine			= @ltelemedicine,
		memberportalaccessfrom	= @lmemberportalaccessfrom,
		memberportalaccessto	= @lmemberportalaccessto,
		wtaxno					= @lwtaxno,
		wtax					= @lwtax,
		enhancedencryption		= @lenhancedencryption,
		restrictdependentmobile = @lrestrictdependentmobile,
		maxcpddependent			= @lmaxcpddependent,
		maxvpddependent			= @lmaxvpddependent

	WHERE compcode = @lcompcode
	OPTION(RECOMPILE)

	EXEC sp_closesymmetric
	SELECT @lcompcode AS compcode
END



GO

-- ---- sp_updatesalesportalagentcontact ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_updatesalesportalagentcontact] 
	-- Add the parameters for the stored procedure here
	@agentno					Int,
	@emailaddress				Varchar(100),
	@telephone					Varchar(20),
	@mobile						Varchar(20)
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE		@lagentno					Int					= @agentno,
				@lemailaddress				Varchar(100)		= @emailaddress,
				@ltelephone					Varchar(20)			= @telephone,				
				@lmobile					Varchar(20)			= @mobile

    -- Insert statements for procedure here
	UPDATE tblagents 
	SET 
		emailaddress = @lemailaddress,
		telephone = @ltelephone,
		mobile = @lmobile
	WHERE agentno = @agentno

END
GO

-- ---- sp_uploadmemcheckduplicateexcelv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemcheckduplicateexcelv2]
	@portalcode		INT,
	@seekby			TINYINT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	INT = @portalcode,
			@lseekby		TINYINT = @seekby,
			@luploadtype	Varchar(10) = ''

	SELECT @luploadtype = uploadtype
	FROM tblportalupload
	WHERE portalcode = @portalcode
	OPTION(RECOMPILE);
	
	;WITH DuplicateFinder AS (
        SELECT 
            failedcols, 
            failedremarks,
  
            COUNT(*) OVER (
                PARTITION BY 
                    CASE 
                        -- LNAME + FNAME + BDATE
                        WHEN @luploadtype NOT IN ('A-MP', 'A-MST', 'A-MPREM', 'M-PD', 'M-DOP') AND @seekby = 1 
                            THEN RTRIM(UPPER(lastname)) + RTRIM(UPPER(firstname)) + CAST(CAST(birthdate AS DATE) AS VARCHAR(20))
                        
                        -- LNAME + BDATE
                        WHEN @luploadtype NOT IN ('A-MP', 'A-MST', 'A-MPREM', 'M-PD', 'M-DOP') AND @seekby = 2 
                            THEN RTRIM(UPPER(lastname)) + CAST(CAST(birthdate AS DATE) AS VARCHAR(20))
                        
                        -- MEMBERNO Trimmed
                        WHEN @luploadtype IN ('M-PD', 'M-DOP') 
                            THEN RTRIM(UPPER(memberno))
                        
                        -- MEMBERNO
                        WHEN @luploadtype IN ('A-MP', 'A-MST', 'A-MPREM') 
                            THEN memberno
                    END
            ) as OccurrenceCount,

            CASE 
                WHEN @luploadtype IN ('M-PD', 'M-DOP') THEN ' B;' 
                ELSE ' F;' 
            END as TargetCol,

            CASE 
                WHEN @luploadtype IN ('M-PD', 'M-DOP') THEN ' DUPLICATE MEMBER ID;'
                WHEN @luploadtype IN ('A-MP', 'A-MST', 'A-MPREM') THEN ' DUPLICATE MEMBER ID IN EXCEL;'
                ELSE ' DUPLICATE RECORD IN EXCEL;'
            END as TargetRemark

        FROM tblportaluploaddetails
        WHERE portalcode = @portalcode
	)

    UPDATE DuplicateFinder
    SET failedcols = LTRIM(RTRIM(ISNULL(failedcols, ''))) + TargetCol,
        failedremarks = LTRIM(RTRIM(ISNULL(failedremarks, ''))) + TargetRemark
    WHERE OccurrenceCount > 1;

	--IF @luploadtype NOT IN ('A-MP', 'A-MST', 'A-MPREM', 'M-PD', 'M-DOP')
	--BEGIN
	--	IF @lseekby = 1
	--		-- LNAME + FNAME + BDATE --
	--		BEGIN
	--			UPDATE a SET
	--			failedcols = LTRIM(RTRIM(failedcols)) + ' F;',
	--			failedremarks = LTRIM(RTRIM(failedremarks)) + ' DUPLICATE RECORD IN EXCEL;'
	--			FROM tblportaluploaddetails a
	--			WHERE a.portalcode = @lportalcode 
				
	--			AND RTRIM(UPPER(lastname))+RTRIM(UPPER(firstname))+CAST(CAST(birthdate AS DATE) AS VARCHAR(20)) IN
	--			(
	--				SELECT RTRIM(UPPER(lastname))+RTRIM(UPPER(firstname))+CAST(CAST(birthdate AS DATE) AS VARCHAR(20))
	--				FROM tblportaluploaddetails 
	--				WHERE portalcode = @lportalcode 
	--				GROUP BY RTRIM(UPPER(lastname))+RTRIM(UPPER(firstname))+CAST(CAST(birthdate AS DATE) AS VARCHAR(20))
	--				HAVING COUNT(RTRIM(UPPER(lastname))+RTRIM(UPPER(firstname))+CAST(CAST(birthdate AS DATE) AS VARCHAR(20))) > 1
	--			)
	--			OPTION(RECOMPILE)
	--		END
	--	IF @lseekby = 2
	--		-- LNAME + BDATE --
	--		BEGIN
	--			UPDATE a SET
	--			failedcols = LTRIM(RTRIM(failedcols)) + ' F;',
	--			failedremarks = LTRIM(RTRIM(failedremarks)) + ' DUPLICATE RECORD IN EXCEL;'
	--			FROM tblportaluploaddetails a
	--			WHERE a.portalcode = @lportalcode 
				
	--			AND RTRIM(UPPER(lastname))+CAST(CAST(birthdate AS DATE) AS VARCHAR(20)) IN
	--			(
	--				SELECT RTRIM(UPPER(lastname))+CAST(CAST(birthdate AS DATE) AS VARCHAR(20))
	--				FROM tblportaluploaddetails 
	--				WHERE portalcode = @lportalcode 
	--				GROUP BY RTRIM(UPPER(lastname))+CAST(CAST(birthdate AS DATE) AS VARCHAR(20))
	--				HAVING COUNT(RTRIM(UPPER(lastname))+CAST(CAST(birthdate AS DATE) AS VARCHAR(20))) > 1
	--			)
	--			OPTION(RECOMPILE)
	--		END
	--END


	--IF @luploadtype IN ('M-PD', 'M-DOP')
	--begin
	--	UPDATE a SET
	--			failedcols = LTRIM(RTRIM(failedcols)) + ' B;',
	--			failedremarks = LTRIM(RTRIM(failedremarks)) + ' DUPLICATE MEMBER ID;'
	--			FROM tblportaluploaddetails a
	--			WHERE a.portalcode = @lportalcode AND 
	--			RTRIM(UPPER(memberno)) IN
	--			(SELECT RTRIM(UPPER(memberno))
	--			FROM tblportaluploaddetails 
	--			WHERE portalcode = @lportalcode 
	--			GROUP BY RTRIM(UPPER(memberno))
	--			HAVING COUNT(RTRIM(UPPER(memberno))) > 1)
	--			OPTION(RECOMPILE)
	--end

 --   IF @luploadtype IN ('A-MP', 'A-MST', 'A-MPREM')
	--BEGIN
	--	UPDATE a SET
	--	failedcols = LTRIM(RTRIM(failedcols)) + ' F;',
	--	failedremarks = LTRIM(RTRIM(failedremarks)) + ' DUPLICATE MEMBER ID IN EXCEL;'
	--	FROM tblportaluploaddetails a
	--	WHERE a.portalcode = @lportalcode AND 
	--	a.memberno IN
	--	(SELECT memberno
	--	FROM tblportaluploaddetails 
	--	WHERE portalcode = @lportalcode 
	--	GROUP BY memberno
	--	HAVING COUNT(memberno) > 1)
	--	OPTION(RECOMPILE)
	--END


	SELECT rowno, failedcols, failedremarks
	FROM tblportaluploaddetails
	WHERE portalcode = @lportalcode 
	AND RTRIM(failedremarks) <> ''
END
GO

-- ---- sp_uploadmemcheckduplicatesystemv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemcheckduplicatesystemv2]
	@portalcode		INT,
	@seekby			TINYINT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode			INT = @portalcode,
			@lseekby				INT = @seekby,
			@lcompcode				INT = 0,
			@lenhancedencryption	BIT	= 0

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	SELECT @lcompcode = compcode
	FROM tblportalupload
	WHERE portalcode = @lportalcode

	SELECT @lenhancedencryption = enhancedencryption
	FROM tblcompany
	WHERE compcode = @lcompcode	

	 IF @lseekby = 1
		-- LNAME + FNAME + BDATE --
		BEGIN
			SET @SQL = N'
						DROP TABLE IF EXISTS #CleanMembers;

						SELECT 
							b.membercode, b.memberno, b.statuscode, b.birthdate, b.compcode,
							UPPER(LTRIM(RTRIM(ISNULL('+QUOTENAME(@DBname)+'.dbo.decodercontains(CASE WHEN @lenhancedencryption = 1 THEN bb.llog ELSE b.llog END, 0), '''')))) as CleanLLog,
							UPPER(LTRIM(RTRIM(ISNULL('+QUOTENAME(@DBname)+'.dbo.decodercontains(CASE WHEN @lenhancedencryption = 1 THEN bb.flog ELSE b.flog END, 0), '''')))) as CleanFLog
						INTO #CleanMembers
						FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b
						LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames bb ON b.membercode = bb.membercode AND @lenhancedencryption = 1
						WHERE b.compcode = @lcompcode
			
						UPDATE a SET
							membercode = ISNULL(b.membercode, 0),
							memberno = ISNULL(b.memberno, ''''),
							dummymemberno = ISNULL(b.memberno, ''''),
							uploadtype =  CASE WHEN b.statuscode <> 4 THEN ''R-PD'' ELSE ''F-PD'' END
						FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
						OUTER APPLY (
							SELECT TOP 1 clean.membercode, clean.memberno, clean.statuscode 
							FROM #CleanMembers AS clean
							WHERE UPPER(LTRIM(RTRIM(ISNULL('+QUOTENAME(@DBname)+'.dbo.decodercontains(a.llog, 0), '''')))) = clean.CleanLLog
							AND UPPER(LTRIM(RTRIM(ISNULL('+QUOTENAME(@DBname)+'.dbo.decodercontains(a.flog, 0), '''')))) = clean.CleanFLog
							AND a.birthdate = clean.birthdate
							ORDER BY clean.membercode DESC
						) b
						WHERE a.portalcode = @lportalcode AND b.membercode <> 0
						OPTION(RECOMPILE)

						DROP TABLE #CleanMembers
						'
			--EXEC (@SQL)
			EXEC sys.sp_executesql
			@SQL,
			N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
			@lcompcode = @lcompcode,
			@lenhancedencryption = @lenhancedencryption,
			@lportalcode = @lportalcode
		END
	IF @lseekby = 2	
		-- LNAME + BDATE --
		BEGIN
			SET @SQL = N'
						DROP TABLE IF EXISTS #CleanMembers;

						SELECT 
							b.membercode, b.memberno, b.statuscode, b.birthdate, b.compcode,
							UPPER(LTRIM(RTRIM(ISNULL('+QUOTENAME(@DBname)+'.dbo.decodercontains(CASE WHEN @lenhancedencryption = 1 THEN bb.llog ELSE b.llog END, 0), '''')))) as CleanLLog
						INTO #CleanMembers
						FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b
						LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames bb ON b.membercode = bb.membercode AND @lenhancedencryption = 1
						WHERE b.compcode = @lcompcode
			
						UPDATE a SET
							membercode = ISNULL(b.membercode, 0),
							memberno = ISNULL(b.memberno, ''''),
							dummymemberno = ISNULL(b.memberno, ''''),
							uploadtype =  CASE WHEN b.statuscode <> 4 THEN ''R-PD'' ELSE ''F-PD'' END
						FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
						OUTER APPLY (
							SELECT TOP 1 clean.membercode, clean.memberno, clean.statuscode 
							FROM #CleanMembers AS clean
							WHERE UPPER(LTRIM(RTRIM(ISNULL('+QUOTENAME(@DBname)+'.dbo.decodercontains(a.llog, 0), '''')))) = clean.CleanLLog
							AND a.birthdate = clean.birthdate
							ORDER BY clean.membercode DESC
						) b
						WHERE a.portalcode = @lportalcode AND b.membercode <> 0
						OPTION(RECOMPILE)

						DROP TABLE #CleanMembers;
						'
			--EXEC (@SQL)
			EXEC sys.sp_executesql
			@SQL,
			N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
			@lcompcode = @lcompcode,
			@lenhancedencryption = @lenhancedencryption,
			@lportalcode = @lportalcode
		END
END
GO

-- ---- sp_uploadmemcheckmaxdependents ----
CREATE   PROCEDURE [dbo].[sp_uploadmemcheckmaxdependents]
	@portalcode		Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	Int = @portalcode,
			@lsynchrupload	Bit	= 0

	SELECT @lsynchrupload = synchrupload
	FROM tblportalupload a WITH(NOLOCK)
	OUTER APPLY (SELECT synchrupload FROM tblcompany b WITH(NOLOCK) WHERE a.compcode = b.compcode) b
	WHERE a.portalcode = @lportalcode

	CREATE TABLE #temp_newdeps
	(
		principalcode	Int,
		cpd				Int,
		vpd				Int
	)

	-- COUNT ALL NEW DEPENDENTS
	INSERT INTO #temp_newdeps (principalcode, cpd, vpd)
	SELECT principalcode,
	cpd = COUNT(CASE dependentcoveragetype WHEN 2 THEN 1 ELSE NULL END),
	vpd = COUNT(CASE dependentcoveragetype WHEN 1 THEN 1 ELSE NULL END)
	FROM tblportaluploaddetails WITH(NOLOCK)
	WHERE portalcode = @lportalcode
	AND principalcode <> 0
	AND membercode = 0
	GROUP BY principalcode
	OPTION(RECOMPILE)

	CREATE TABLE #temp_olddeps
	(
		principalcode	Int,
		cpd				Int,
		vpd				Int
	)

	-- COUNT ALL EXISTING DEPENDENTS
	INSERT INTO #temp_olddeps (principalcode, cpd, vpd)
	SELECT principalcode,
	cpd = COUNT(CASE dependentcoveragetype WHEN 2 THEN 1 ELSE NULL END),
	vpd = COUNT(CASE dependentcoveragetype WHEN 1 THEN 1 ELSE NULL END)
	FROM tblmembers a WITH(NOLOCK)
	OUTER APPLY (SELECT dependentcoveragetype FROM tblmemberdetails b WITH(NOLOCK) WHERE a.compcode = b.compcode AND a.membercode = b.membercode) b
	WHERE principalcode IN (
		SELECT principalcode
		FROM #temp_newdeps
	)
	GROUP BY principalcode
	OPTION(RECOMPILE)

	CREATE TABLE #temp_stagingdeps
	(
		principalcode	Int,
		cpd				Int,
		vpd				Int
	)

	IF @lsynchrupload = 0
	BEGIN
		INSERT INTO #temp_stagingdeps (principalcode, cpd, vpd)
		SELECT principalcode,
		cpd = COUNT(CASE dependentcoveragetype WHEN 2 THEN 1 ELSE NULL END),
		vpd = COUNT(CASE dependentcoveragetype WHEN 1 THEN 1 ELSE NULL END)
		FROM maswebkituat.dbo.tblwebcompanymembers WITH(NOLOCK)
		WHERE principalcode IN (
			SELECT principalcode
			FROM #temp_newdeps
		)
		GROUP BY principalcode
		OPTION(RECOMPILE)
	END

	UPDATE a SET
	failedcols = LTRIM(RTRIM(failedcols)) + ' T;',
	failedremarks = LTRIM(RTRIM(failedremarks)) + ' MAX CPD/VPD DEPENDENTS HAS EXCEEDED;'
	FROM tblportaluploaddetails a WITH(NOLOCK)
	OUTER APPLY (SELECT cpd, vpd FROM #temp_newdeps b WITH(NOLOCK) WHERE a.principalcode = b.principalcode) b
	OUTER APPLY (SELECT cpd, vpd FROM #temp_olddeps c WITH(NOLOCK) WHERE a.principalcode = c.principalcode) c
	OUTER APPLY (SELECT cpd, vpd FROM #temp_stagingdeps d WITH(NOLOCK) WHERE a.principalcode = d.principalcode) d
	OUTER APPLY (SELECT maxcpddependent, maxvpddependent FROM tblcompany e WITH(NOLOCK) WHERE a.compcode = e.compcode) e
	WHERE portalcode = @lportalcode
	AND principalcode <> 0
	AND
	(
		(ISNULL(e.maxcpddependent, 0) <> 0 AND ISNULL(b.cpd, 0) + ISNULL(c.cpd, 0) + ISNULL(d.cpd, 0) > ISNULL(e.maxcpddependent, 0))
		OR
		(ISNULL(e.maxvpddependent, 0) <> 0 AND ISNULL(b.vpd, 0) + ISNULL(c.vpd, 0) + ISNULL(d.vpd, 0) > ISNULL(e.maxvpddependent, 0))
	)
	OPTION(RECOMPILE)

	DROP TABLE #temp_newdeps, #temp_olddeps, #temp_stagingdeps

	SELECT rowno, failedcols, failedremarks
	FROM tblportaluploaddetails WITH(NOLOCK)
	WHERE portalcode = @lportalcode AND RTRIM(failedremarks) <> ''
	OPTION(RECOMPILE)

END
GO

-- ---- sp_uploadmemcheckmaxdependentsv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemcheckmaxdependentsv2]
	@portalcode		Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	Int = @portalcode,
			@lsynchrupload	Bit	= 0

	SELECT @lsynchrupload = b.synchrupload
	FROM tblportalupload a WITH(NOLOCK)
	LEFT JOIN tblcompany b WITH(NOLOCK) ON a.compcode = b.compcode
	WHERE a.portalcode = @lportalcode


	CREATE TABLE #temp_newdeps
	(
		principalcode	Int,
		cpd				Int NOT NULL DEFAULT 0,
		vpd				Int NOT NULL DEFAULT 0
	)

	-- COUNT ALL NEW DEPENDENTS
	INSERT INTO #temp_newdeps (principalcode, cpd, vpd)
	SELECT principalcode,
	cpd = SUM(CASE dependentcoveragetype WHEN 2 THEN 1 ELSE 0 END),
	vpd = SUM(CASE dependentcoveragetype WHEN 1 THEN 1 ELSE 0 END)
	FROM tblportaluploaddetails WITH(NOLOCK)
	WHERE portalcode = @lportalcode
	AND principalcode <> 0
	AND membercode = 0
	GROUP BY principalcode
	OPTION(RECOMPILE)

	CREATE TABLE #temp_olddeps
	(
		principalcode	Int,
		cpd				Int NOT NULL DEFAULT 0,
		vpd				Int NOT NULL DEFAULT 0
	)

	-- COUNT ALL EXISTING DEPENDENTS
	INSERT INTO #temp_olddeps (principalcode, cpd, vpd)
	SELECT principalcode,
	cpd = SUM(CASE dependentcoveragetype WHEN 2 THEN 1 ELSE 0 END),
	vpd = SUM(CASE dependentcoveragetype WHEN 1 THEN 1 ELSE 0 END)
	FROM tblmembers a WITH(NOLOCK)
	LEFT JOIN tblmemberdetails b WITH(NOLOCK) ON a.compcode = b.compcode AND a.membercode = b.membercode
	WHERE principalcode IN (
		SELECT principalcode
		FROM #temp_newdeps
	)
	GROUP BY principalcode
	OPTION(RECOMPILE)

	CREATE TABLE #temp_stagingdeps
	(
		principalcode	Int,
		cpd				Int NOT NULL DEFAULT 0,
		vpd				Int NOT NULL DEFAULT 0
	)


	IF @lsynchrupload = 0
	BEGIN
		INSERT INTO #temp_stagingdeps (principalcode, cpd, vpd)
		SELECT principalcode,
		cpd = COUNT(CASE dependentcoveragetype WHEN 2 THEN 1 ELSE NULL END),
		vpd = COUNT(CASE dependentcoveragetype WHEN 1 THEN 1 ELSE NULL END)
		FROM maswebkituat.dbo.tblwebcompanymembers a WITH(NOLOCK)
		WHERE EXISTS (
			SELECT 1
			FROM #temp_newdeps b
			WHERE b.principalcode = a.principalcode
		)
		GROUP BY principalcode
		OPTION(RECOMPILE)
	END

	UPDATE a SET
	failedcols = LTRIM(RTRIM(failedcols)) + ' T;',
	failedremarks = LTRIM(RTRIM(failedremarks)) + ' MAX CPD/VPD DEPENDENTS HAS EXCEEDED;'
	FROM tblportaluploaddetails a WITH(NOLOCK)
	LEFT JOIN #temp_newdeps b WITH(NOLOCK) ON a.principalcode = b.principalcode
	LEFT JOIN #temp_olddeps c WITH(NOLOCK) ON a.principalcode = c.principalcode
	LEFT JOIN #temp_stagingdeps d WITH(NOLOCK) ON a.principalcode = d.principalcode
	LEFT JOIN tblcompany e WITH(NOLOCK) ON a.compcode = e.compcode
	WHERE portalcode = @lportalcode
	AND a.principalcode <> 0
	AND
	(
		(ISNULL(e.maxcpddependent, 0) <> 0 AND ISNULL(b.cpd, 0) + ISNULL(c.cpd, 0) + ISNULL(d.cpd, 0) > ISNULL(e.maxcpddependent, 0))
		OR
		(ISNULL(e.maxvpddependent, 0) <> 0 AND ISNULL(b.vpd, 0) + ISNULL(c.vpd, 0) + ISNULL(d.vpd, 0) > ISNULL(e.maxvpddependent, 0))
	)
	OPTION(RECOMPILE)

	DROP TABLE #temp_newdeps, #temp_olddeps, #temp_stagingdeps

	SELECT rowno, failedcols, failedremarks
	FROM tblportaluploaddetails WITH(NOLOCK)
	WHERE portalcode = @lportalcode AND RTRIM(failedremarks) <> ''
	OPTION(RECOMPILE)

END
GO

-- ---- sp_uploadmemchecknonmembersv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemchecknonmembersv2]
	@portalcode		INT,
	@seekby			TINYINT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DROP TABLE IF EXISTS #CleanMembers;

	DECLARE @lportalcode	INT = @portalcode,
			@lseekby		INT = @seekby,
			@lcompcode		INT = 0,
			@lcols			Varchar(20) = 'Y;Z;AA;'

	DECLARE @SQL			Varchar(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	SELECT @lcompcode = compcode
	FROM tblportalupload
	WHERE portalcode = @lportalcode

    IF @lseekby = 1
		-- LNAME + BDATE --
		BEGIN
			DROP TABLE IF EXISTS #CleanMembers;

			SELECT 
				b.membercode, b.memberno, b.statuscode, b.birthdate, b.compcode, b.nonmember,
				UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(b.llog, 0), '')))) as CleanLLog
			INTO #CleanMembers
			FROM tblmembers b
			WHERE b.compcode = @lcompcode

			UPDATE a SET 
			failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
			failedremarks = LTRIM(RTRIM(failedremarks))+ Upper(' This is a Non-Member')
			FROM tblportaluploaddetails a WITH(NOLOCK)
			OUTER APPLY (
				SELECT TOP 1 membercode, nonmember 
				FROM #CleanMembers b 
				WHERE UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.llog, 0), '')))) = b.CleanLLog
				AND a.birthdate = b.birthdate) b
			WHERE a.portalcode = @lportalcode and b.membercode <> 0 AND b.nonmember = 1

			OPTION(RECOMPILE)

			DROP TABLE #CleanMembers

			--SET @SQL = 'UPDATE a SET 
			--failedcols = LTRIM(RTRIM(failedcols))+ '+@lcols+',
			--failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' This is a Non-Member'')
			--FROM tblportaluploaddetails a WITH(NOLOCK)
			--OUTER APPLY (SELECT membercode, nonmember FROM '+@DBname+'.dbo.tblmembers b WHERE b.compcode = '+CONVERT(VARCHAR(20), @lcompcode)+' AND UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.llog, 0), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(b.llog, 0), '''')))) AND UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.flog, 0), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(b.flog, 0), '''')))) AND a.birthdate = b.birthdate) b
			--WHERE a.portalcode = '+CONVERT(VARCHAR(20), @lportalcode)+' and b.membercode <> 0 AND b.nonmember = 1
			--OPTION(RECOMPILE)'

			--EXEC (@SQL)
		END
	IF @lseekby = 2	
		-- LNAME + FNAME + BDATE --
		BEGIN
			DROP TABLE IF EXISTS #CleanMembers2;

			SELECT 
				b.membercode, b.memberno, b.statuscode, b.birthdate, b.compcode, b.nonmember,
				UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(b.llog, 0), '')))) as CleanLLog,
				UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(b.flog, 0), '')))) as CleanFLog
			INTO #CleanMembers2
			FROM tblmembers b
			WHERE b.compcode = @lcompcode

			UPDATE a SET 
			failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
			failedremarks = LTRIM(RTRIM(failedremarks))+ Upper(' This is a Non-Member')
			FROM tblportaluploaddetails a WITH(NOLOCK)
			OUTER APPLY (
				SELECT TOP 1 membercode, nonmember 
				FROM #CleanMembers2 b 
				WHERE UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.llog, 0), '')))) = b.CleanLLog
				AND UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.flog, 0), '')))) = b.CleanFLog 
				AND a.birthdate = b.birthdate) b
			WHERE a.portalcode = @lportalcode and b.membercode <> 0 AND b.nonmember = 1

			OPTION(RECOMPILE)

			DROP TABLE #CleanMembers2

			--SET @SQL = 'UPDATE a SET 
			--failedcols = LTRIM(RTRIM(failedcols))+ '+@lcols+',
			--failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' This is a Non-Member'')
			--FROM tblportaluploaddetails a WITH(NOLOCK)
			--OUTER APPLY (SELECT membercode, nonmember FROM '+@DBname+'.dbo.tblmembers b WHERE b.compcode = '+CONVERT(VARCHAR(20), @lcompcode)+' AND UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.llog, 0), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(b.llog, 0), '''')))) AND UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.flog, 0), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(dbo.decodercontains(b.flog, 0), '''')))) AND a.birthdate = b.birthdate) b
			--WHERE a.portalcode = '+CONVERT(VARCHAR(20), @lportalcode)+' and b.membercode <> 0 AND b.nonmember = 1
			--OPTION(RECOMPILE)'

			--EXEC (@SQL)
		END

	SELECT rowno, failedcols, failedremarks
	FROM tblportaluploaddetails
	WHERE portalcode = @lportalcode AND RTRIM(failedremarks) <> ''
END
GO

-- ---- sp_uploadmemcheckprincipalv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemcheckprincipalv2]
	 --Add the parameters for the stored procedure here
	@portalcode Int
AS
BEGIN
	 --SET NOCOUNT ON added to prevent extra result sets from
	 --interfering with SELECT statements.
	SET NOCOUNT ON;
	DECLARE @lportalcode		Int			= @portalcode,
			@lseekby			Int			= 0,
			@luploadtype		Varchar(20) = '',
			@lfailed			Int			= 0,
			@lcompcode			Int			= 0,
			@lparentcompcode	Int			= 0,
			@lcols				Varchar(20) = ''

	DECLARE @SQL					NVARCHAR(MAX)	= '',
			@enhancedencryption		Bit				= 0,
			@DBname					Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	SELECT @lcompcode = compcode, @luploadtype = uploadtype, @lseekby = seekby,
	@lcols = CASE WHEN retail = 1 THEN 'X;Y;Z;' WHEN uploadtype = 'M-PD' THEN 'Z;AA;AB;' ELSE 'Y;Z;AA;' END
	FROM tblportalupload WITH(NOLOCK)
	WHERE portalcode = @lportalcode

	SELECT @enhancedencryption = enhancedencryption
	FROM tblcompany WHERE compcode = @lcompcode

	exec sp_opensymmetric

	IF @luploadtype = 'NR-PD' or @luploadtype = 'M-PD'
		BEGIN

			-- DEPENDENT EMP NO SHOULD HAVE PRINCIPAL IN THE FILE --
			IF @lseekby = 2
			BEGIN
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has no match with the Principal records on the Excel and System'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				WHERE a.portalcode = @lportalcode AND a.classorder = 1 
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK)
					WHERE b.portalcode = @lportalcode AND b.classorder = 0
					AND RTRIM(UPPER(b.mname)) = RTRIM(UPPER(a.pmname)) 
					AND b.birthdate = a.pbirthdate
				)
				
				AND NOT EXISTS 
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK)
					OUTER APPLY (SELECT TOP 1 newvalue FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberamendment c WITH(NOLOCK) WHERE a.compcode = c.compcode AND c.statuscode <> 3 AND c.amendmenttype = 18 AND b.membercode = c.membercode ORDER BY effectivity DESC) c 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames d WITH(NOLOCK) ON d.membercode = b.membercode
					WHERE (b.compcode = @lcompcode) and b.classorder =0 and b.statuscode NOT IN (3, 8) and ISNULL(c.newvalue, b.expiry) >= a.effectivity
					AND RTRIM(UPPER(IIF(@enhancedencryption = 1,  d.llog, b.llog))) = RTRIM(UPPER(a.pllog)) 
					AND b.birthdate = a.pbirthdate
				)
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@enhancedencryption BIT, @lportalcode INT, @lcols VARCHAR(20), @lcompcode INT',
				@enhancedencryption = @enhancedencryption,
				@lportalcode = @lportalcode,
				@lcols = @lcols,
				@lcompcode = @lcompcode;
				
				--CHECK PRINCIPAL EFFECTIVITY ON EXCEL
				UPDATE a SET 
				failedcols = LTRIM(RTRIM(a.failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(a.failedremarks))+ Upper(' Dependent effectivity must not be earlier than Principal effectivity')
				FROM tblportaluploaddetails a WITH(NOLOCK)
				LEFT JOIN dbo.tblportaluploaddetails b WITH(NOLOCK) 
				ON b.classorder = 0 
				AND a.portalcode = b.portalcode 
				AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(b.llog)) 
				AND a.effectivity < b.effectivity

				WHERE a.portalcode = @lportalcode AND a.classorder = 1 AND b.portalcode <> 0 AND a.effectivity < b.effectivity
				OPTION(RECOMPILE)

				--CHECK PRINCIPAL EFFECTIVITY ON SYSTEM --removed d coz it's unused.
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(a.failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(a.failedremarks))+ Upper('' Dependent effectivity must not be earlier than Principal effectivity'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
				ON c.compcode = @lcompcode
				AND c.classorder = 0 
				AND RTRIM(UPPER(c.llog)) =  RTRIM(UPPER(a.pllog)) 
				AND a.pbirthdate = c.birthdate 
				AND a.effectivity < c.effectivity
				WHERE a.portalcode = @lportalcode AND a.classorder = 1 AND c.compcode <> 0 AND a.effectivity < c.origeffectivity
				OPTION(RECOMPILE)
				'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lcompcode INT, @lportalcode INT, @lcols VARCHAR(20)',
				@lcompcode = @lcompcode,
				@lportalcode = @lportalcode,
				@lcols = @lcols;

				--CHECK IF PRINCIPAL HAS CHANGED
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has changed since last cut-off'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				OUTER APPLY (
					SELECT membercode FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK) 
					WHERE b.classorder = 0 
					AND a.compcode = b.compcode 
					AND RTRIM(UPPER(b.llog)) =  RTRIM(UPPER(a.pllog)) 
					AND b.birthdate = a.pbirthdate
				) b
				OUTER APPLY (
					SELECT principalcode 
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					WHERE a.compcode = c.compcode AND a.membercode = c.membercode
				) c
				WHERE a.classorder = 1 
				AND a.portalcode = @lportalcode 
				AND a.membercode <> 0 
				AND ISNULL(b.membercode, 0) <> ISNULL(c.principalcode, 0)
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lportalcode INT, @lcols VARCHAR(20)',
				@lportalcode = @lportalcode,
				@lcols = @lcols;

				--CHECK IF PRINCIPAL IS FOR RENEWAL
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has not been renewed this cut-off'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				WHERE a.portalcode = @lportalcode AND a.classorder = 1 
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK)
					WHERE b.portalcode = @lportalcode AND b.classorder = 0
					AND RTRIM(UPPER(b.mname)) = RTRIM(UPPER(a.pmname))
					AND b.birthdate = a.pbirthdate
				)
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK)
					OUTER APPLY (SELECT TOP 1 newvalue FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberamendment c WITH(NOLOCK) WHERE a.compcode = c.compcode AND c.statuscode <> 3 AND c.amendmenttype = 18 AND b.membercode = c.membercode ORDER BY effectivity DESC) c
					OUTER APPLY (SELECT TOP 1 newvalue FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberamendment d WITH(NOLOCK) WHERE a.compcode = d.compcode AND d.statuscode <> 3 AND d.amendmenttype = 17 AND b.membercode = d.membercode ORDER BY effectivity DESC) d
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames e WITH(NOLOCK) ON e.membercode = b.membercode
					WHERE (b.compcode = @lcompcode) and b.classorder =0 and b.statuscode NOT IN (3, 8) and ISNULL(c.newvalue, b.expiry) >= a.effectivity AND a.effectivity >= b.origeffectivity
					AND RTRIM(UPPER(IIF(@enhancedencryption = 1,  e.llog,b.llog))) = RTRIM(UPPER(a.pllog))
					AND b.birthdate = a.pbirthdate
				)
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lportalcode INT, @lcols VARCHAR(20), @lcompcode INT, @enhancedencryption BIT',
				@lportalcode = @lportalcode,
				@lcols = @lcols,
				@lcompcode = @lcompcode,
				@enhancedencryption = @enhancedencryption

			END

			ELSE
			BEGIN
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has no match with the Principal records on the Excel and System'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				WHERE a.portalcode = @lportalcode AND a.classorder = 1 
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK)
					WHERE b.portalcode = @lportalcode AND b.classorder = 0
					AND RTRIM(UPPER(b.mname)) = RTRIM(UPPER(a.pmname)) 
					AND b.birthdate = a.pbirthdate
				)
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK)
					OUTER APPLY (SELECT TOP 1 newvalue FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberamendment c WITH(NOLOCK) WHERE a.compcode = c.compcode AND c.statuscode <> 3 AND c.amendmenttype = 18 AND b.membercode = c.membercode ORDER BY effectivity DESC) c
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames e WITH(NOLOCK) ON e.membercode = b.membercode
					WHERE (b.compcode = @lcompcode) and b.classorder =0 and b.statuscode NOT IN (3, 8) and ISNULL(c.newvalue, b.expiry) >= a.effectivity
					AND RTRIM(UPPER(IIF(@enhancedencryption = 1,  e.llog,b.llog))) = RTRIM(UPPER(a.pllog))
					AND RTRIM(UPPER(IIF(@enhancedencryption = 1,  e.flog,b.flog))) = RTRIM(UPPER(a.pflog))
					AND b.birthdate = a.pbirthdate
				
				)
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lportalcode INT, @lcols VARCHAR(20), @lcompcode INT, @enhancedencryption BIT',
				@lportalcode = @lportalcode,
				@lcols = @lcols,
				@lcompcode = @lcompcode,
				@enhancedencryption = @enhancedencryption

				--CHECK PRINCIPAL EFFECTIVITY ON EXCEL
				UPDATE a SET 
				failedcols = LTRIM(RTRIM(a.failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(a.failedremarks))+ Upper(' Dependent effectivity must not be earlier than Principal effectivity')
				FROM tblportaluploaddetails a WITH(NOLOCK)
				LEFT JOIN tblportaluploaddetails b WITH(NOLOCK) ON b.classorder = 0 AND a.portalcode = b.portalcode and RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(b.llog))
				WHERE a.portalcode = @lportalcode AND a.classorder = 1 AND b.portalcode <> 0 AND a.effectivity < b.effectivity
				OPTION(RECOMPILE)

				--CHECK PRINCIPAL EFFECTIVITY ON SYSTEM --d removed
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Dependent effectivity must not be earlier than Principal effectivity'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
				ON c.compcode = @lcompcode 
				AND c.classorder = 0 
				AND RTRIM(UPPER(c.llog)) =  RTRIM(UPPER(a.pllog)) 
				AND RTRIM(UPPER(c.flog)) =  RTRIM(UPPER(a.pflog)) 
				AND a.pbirthdate = c.birthdate 
				AND a.effectivity < c.effectivity
				OUTER APPLY (
					SELECT TOP 1 newvalue 
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberamendment d WITH(NOLOCK) 
					WHERE a.compcode = d.compcode 
					AND d.statuscode <> 3 
					AND d.amendmenttype = 17 
					AND c.membercode = d.membercode 
					ORDER BY effectivity DESC
				) d
				WHERE a.portalcode = @lportalcode AND a.classorder = 1 AND c.compcode <> 0 AND a.effectivity < c.origeffectivity
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lcols VARCHAR(20), @lportalcode INT, @lcompcode INT',
				@lcols = @lcols,
				@lportalcode = @lportalcode,
				@lcompcode = @lcompcode

				--CHECK IF PRINCIPAL HAS CHANGED
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has changed since last cut-off'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK) 
				ON b.classorder = 0 
				AND a.compcode = b.compcode 
				AND RTRIM(UPPER(b.llog)) =  RTRIM(UPPER(a.pllog)) 
				AND RTRIM(UPPER(b.flog)) =  RTRIM(UPPER(a.pflog)) 
				AND b.birthdate = a.pbirthdate
				LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
				ON a.compcode = c.compcode 
				AND a.membercode = c.membercode
				WHERE a.classorder = 1 AND a.portalcode = @lportalcode AND a.membercode <> 0 AND ISNULL(b.membercode, 0) <> ISNULL(c.principalcode, 0)
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lcols VARCHAR(20), @lportalcode INT',
				@lcols = @lcols,
				@lportalcode = @lportalcode

				--CHECK IF PRINCIPAL IS FOR RENEWAL  --d removed
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has not been renewed this cut-off'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				WHERE a.portalcode = @lportalcode AND a.classorder = 1 
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK)
					WHERE b.portalcode = @lportalcode AND b.classorder = 0
					AND RTRIM(UPPER(b.mname)) = RTRIM(UPPER(a.pmname))
					AND b.birthdate = a.pbirthdate
				)
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK)
					OUTER APPLY (SELECT TOP 1 newvalue FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberamendment c WITH(NOLOCK) WHERE a.compcode = c.compcode AND c.statuscode <> 3 AND c.amendmenttype = 18 AND b.membercode = c.membercode ORDER BY effectivity DESC) c
					LEFT JOIN  '+QUOTENAME(@DBname)+'.dbo.tblmembernames e WITH(NOLOCK) 
					ON e.membercode = b.membercode
					WHERE (b.compcode = @lcompcode) and b.classorder = 0 and b.statuscode NOT IN (3, 8) and ISNULL(c.newvalue, b.expiry) >= a.effectivity AND a.effectivity >= b.origeffectivity
					AND RTRIM(UPPER(IIF(@enhancedencryption = 1,  e.llog,b.llog))) =  RTRIM(UPPER(a.pllog))
					AND RTRIM(UPPER(IIF(@enhancedencryption = 1,  e.flog,b.flog))) = RTRIM(UPPER(a.pflog))
					AND b.birthdate = a.pbirthdate
				)
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lportalcode INT, @lcols VARCHAR(20), @lcompcode INT, @enhancedencryption BIT',
				@lportalcode = @lportalcode,
				@lcols = @lcols,
				@lcompcode = @lcompcode,
				@enhancedencryption = @enhancedencryption
			END
		END

	IF @luploadtype = 'NR-DOP'
		BEGIN
			-- GET PARENTCOMPCODE --
			SELECT @lparentcompcode = parentcompcode
			FROM tblcompany WITH(NOLOCK)
			WHERE compcode = @lcompcode
			-- DEPENDENT EMP NO SHOULD HAVE PRINCIPAL IN THE COMPANY --
			IF @lseekby = 1
			BEGIN
				SET @SQL =
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has no match with the Principal records on the System'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				WHERE a.portalcode = @lportalcode 
				AND a.classorder = 1 
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK)
					OUTER APPLY (SELECT TOP 1 newvalue FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberamendment c WITH(NOLOCK) WHERE b.compcode = c.compcode AND c.statuscode <> 3 AND c.amendmenttype = 18 AND b.membercode = c.membercode ORDER BY effectivity DESC) c
					WHERE (b.compcode = @lparentcompcode) 
					AND b.classorder = 0 
					AND b.statuscode NOT IN (3, 8) 
					AND ISNULL(c.newvalue, b.expiry) >= a.expiry
					AND RTRIM(UPPER(b.llog)) = a.pllog
					AND b.birthdate = a.pbirthdate
				)
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lportalcode INT, @lcols VARCHAR(20), @lparentcompcode INT',
				@lportalcode = @lportalcode,
				@lcols = @lcols,
				@lparentcompcode = @lparentcompcode

				--CHECK PRINCIPAL EFFECTIVITY ON SYSTEM
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Dependent effectivity must not be earlier than Principal effectivity'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
				ON c.compcode = @lparentcompcode AND c.classorder = 0 
				AND RTRIM(UPPER(c.mdflog)) =  RTRIM(UPPER(a.pmdflog)) 
				AND a.pbirthdate = c.birthdate 
				AND a.effectivity < c.effectivity
				WHERE a.portalcode = @lportalcode AND a.classorder = 1 AND c.compcode <> 0 AND a.effectivity < c.origeffectivity
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lportalcode INT, @lcols VARCHAR(20), @lparentcompcode INT',
				@lportalcode = @lportalcode,
				@lcols = @lcols,
				@lparentcompcode = @lparentcompcode

			END

			IF @lseekby = 2
			BEGIN
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has no match with the Principal records on the System'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				WHERE a.portalcode = @lportalcode
				AND a.classorder = 1 
				AND NOT EXISTS
				(
					SELECT 1
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK)
					OUTER APPLY (SELECT TOP 1 newvalue FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberamendment c WITH(NOLOCK) WHERE b.compcode = c.compcode AND c.statuscode <> 3 AND c.amendmenttype = 18 AND b.membercode = c.membercode ORDER BY effectivity DESC) c
					WHERE (b.compcode = @lparentcompcode) 
					AND b.classorder =0 
					AND b.statuscode NOT IN (3, 8) 
					AND ISNULL(c.newvalue, b.expiry) >= a.expiry
					AND RTRIM(UPPER(b.llog)) = a.pllog
					AND b.birthdate = a.pbirthdate
				)
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lportalcode INT, @lcols VARCHAR(20), @lparentcompcode INT',
				@lportalcode = @lportalcode,
				@lcols = @lcols,
				@lparentcompcode = @lparentcompcode

				--CHECK PRINCIPAL EFFECTIVITY ON SYSTEM
				SET @SQL = 
				N'UPDATE a SET 
				failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
				failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Dependent effectivity must not be earlier than Principal effectivity'')
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
				ON c.compcode = @lparentcompcode
				AND c.classorder = 0 
				AND RTRIM(UPPER(c.mdflog)) =  RTRIM(UPPER(a.pmdflog)) 
				AND a.pbirthdate = c.birthdate 
				AND a.effectivity < c.effectivity

				WHERE a.portalcode = @lportalcode AND a.classorder = 1 AND c.compcode <> 0 AND a.effectivity < c.origeffectivity
				OPTION(RECOMPILE)'

				--EXEC (@SQL)
				EXEC sys.sp_executesql
				@SQL,
				N'@lportalcode INT, @lcols VARCHAR(20), @lparentcompcode INT',
				@lportalcode = @lportalcode,
				@lcols = @lcols,
				@lparentcompcode = @lparentcompcode
			END
		END

	IF @luploadtype = 'R-NR-PD'
	BEGIN

		-- DEPENDENT EMP NO SHOULD HAVE PRINCIPAL IN THE FILE --
		IF @lseekby = 1
		BEGIN
			SET @SQL = 
			N'UPDATE a SET 
			failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
			failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Principal has no match with the Principal records on the Excel and System'')
			FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
			WHERE a.portalcode = @lportalcode 
			AND a.classorder = 1 
			AND NOT EXISTS
			(
				SELECT 1
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK)
				WHERE b.portalcode = @lportalcode AND classorder = 0
				AND RTRIM(UPPER(b.llog)) = RTRIM(UPPER(a.pllog))
				AND RTRIM(UPPER(b.flog)) = RTRIM(UPPER(a.pflog))
				AND b.birthdate = a.pbirthdate
			)
			AND NOT EXISTS 
			(
				SELECT 1
				FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK)
				OUTER APPLY (SELECT llog, flog FROM '+QUOTENAME(@DBname)+'.dbo.tblmembernames e WITH(NOLOCK) WHERE e.membercode = b.membercode) e 
				WHERE (b.compcode = @lcompcode) and b.classorder = 0
				AND RTRIM(UPPER(IIF(@enhancedencryption = 1,  e.llog,b.llog))) = RTRIM(UPPER(a.pllog))
				AND RTRIM(UPPER(IIF(@enhancedencryption = 1,  e.flog,b.flog))) = RTRIM(UPPER(a.pflog))
				AND b.birthdate = a.pbirthdate
			)
			OPTION(RECOMPILE)'

			--EXEC (@SQL)
			EXEC sys.sp_executesql
			@SQL,
			N'@lportalcode INT, @lcols VARCHAR(20), @enhancedencryption BIT, @lcompcode INT',
			@lportalcode = @lportalcode,
			@lcols = @lcols,
			@enhancedencryption = @enhancedencryption,
			@lcompcode = @lcompcode

			--CHECK PRINCIPAL EFFECTIVITY ON EXCEL
			UPDATE a SET 
			failedcols = LTRIM(RTRIM(a.failedcols))+ @lcols,
			failedremarks = LTRIM(RTRIM(a.failedremarks))+ Upper(' Dependent effectivity must not be earlier than Principal effectivity')
			FROM tblportaluploaddetails a WITH(NOLOCK)
			LEFT JOIN tblportaluploaddetails b WITH(NOLOCK) 
			ON b.classorder = 0 
			AND a.portalcode = b.portalcode 
			AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(b.llog)) 
			AND RTRIM(UPPER(a.pflog)) = RTRIM(UPPER(b.flog)) 
			AND a.effectivity < b.effectivity

			WHERE a.portalcode = @lportalcode AND a.classorder = 1 AND b.portalcode <> 0 AND a.effectivity < b.effectivity
			OPTION(RECOMPILE)

			--CHECK PRINCIPAL EFFECTIVITY ON SYSTEM
			SET @SQL = 
			N'UPDATE a SET 
			failedcols = LTRIM(RTRIM(failedcols))+ @lcols,
			failedremarks = LTRIM(RTRIM(failedremarks))+ Upper('' Dependent effectivity must not be earlier than Principal effectivity'')
			FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
			LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
			ON c.compcode = @lcompcode 
			AND c.classorder = 0 
			AND RTRIM(UPPER(c.llog)) =  RTRIM(UPPER(a.pllog)) 
			AND RTRIM(UPPER(c.flog)) =  RTRIM(UPPER(a.pflog)) 
			AND a.pbirthdate = c.birthdate 
			and a.effectivity < c.effectivity
			WHERE a.portalcode = @lportalcode AND a.classorder = 1 AND c.compcode <> 0 AND a.effectivity < c.origeffectivity
			OPTION(RECOMPILE)'

			--EXEC (@SQL)
			EXEC sys.sp_executesql
			@SQL,
			N'@lportalcode INT, @lcols VARCHAR(20), @lcompcode INT',
			@lportalcode = @lportalcode,
			@lcols = @lcols,
			@lcompcode = @lcompcode
		END

			
	END

	
	exec sp_closesymmetric

	SELECT rowno, failedcols, failedremarks
	FROM tblportaluploaddetails WITH(NOLOCK)
	WHERE portalcode = @lportalcode AND RTRIM(failedremarks) <> ''
END
GO

-- ---- sp_uploadmemgetamendmentmembersv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_uploadmemgetamendmentmembersv2]
	-- Add the parameters for the stored procedure here
	
	@compcode		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lcompcode		Int				= @compcode

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	EXEC sp_opensymmetric

	SET @SQL = N'SELECT  a.membercode, a.memberno, a.classorder, a.membercategory, a.principalcode, a.civilstatus,a.effectivity,
	ISNULL(b.civilstatus, 0) AS princivilstatus,a.llog,a.flog, a.gender,
	firstname = LTRIM(RTRIM('+QUOTENAME(@DBname)+'.dbo.Decrypt(a.firstname))),
	miname = LTRIM(RTRIM('+QUOTENAME(@DBname)+'.dbo.Decrypt(a.miname))),
	lastname = LTRIM(RTRIM('+QUOTENAME(@DBname)+'.dbo.Decrypt(a.lastname))),
	membername = LTRIM(RTRIM('+QUOTENAME(@DBname)+'.dbo.Decrypt(a.membername)))
	FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers a WITH(NOLOCK)
	LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK) ON a.principalcode = b.membercode
	WHERE a.compcode = @lcompcode AND a.compcode <> 0 AND a.inactivedate = ''1900-01-01''
	OPTION(RECOMPILE)'

	EXEC master.sys.sp_executesql
	@SQL,
	N'@lcompcode INT',
	@lcompcode = @lcompcode

	EXEC sp_closesymmetric

	--SELECT  a.membercode, a.memberno, a.classorder, a.membercategory, a.principalcode, a.civilstatus,a.effectivity,
	--ISNULL(b.civilstatus, 0) AS princivilstatus,a.llog,a.flog, a.gender,
	--firstname = LTRIM(RTRIM(dbo.Decrypt(a.firstname))),
	--miname = LTRIM(RTRIM(dbo.Decrypt(a.miname))),
	--lastname = LTRIM(RTRIM(dbo.Decrypt(a.lastname))),
	--membername = LTRIM(RTRIM(dbo.Decrypt(a.membername)))
	--FROM tblmembers a
	--OUTER APPLY (SELECT civilstatus,membercode FROM tblmembers b WiTH(NOLOCK) WHERE a.principalcode = b.membercode) b
	--WHERE a.compcode = @lcompcode AND a.compcode <> 0 AND a.inactivedate = '01/01/1900'
	--OPTION(RECOMPILE)

END
GO

-- ---- sp_uploadmemgetcompanyinfov2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemgetcompanyinfov2] --57
	-- Add the parameters for the stored procedure here
	
	@compcode		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lcompcode		Int		= @compcode
		
	SELECT companyname = dbo.decoder(a.ldflog, 0),
	a.contractno, a.companytype, a.statuscode, a.coveredfrom, a.coveredto, a.effectivity, 
	a.expiry, a.companysetup, a.billingschedule, a.memberposition, 
	ISNULL(b.recordcode, '') membertype, 
	ISNULL(b.recordcode, '') companytypecode,
	ISNULL(b.recordno, 0) companytyperecord, 
	ISNULL(c.effectivity, '1900-01-01' ) as contracteffectivity, 
	ISNULL(c.expiry, '1900-01-01') as contractexpiry,
	a.maxcpddependent, a.maxvpddependent
	FROM tblcompany a WITH(NOLOCK)
	LEFT JOIN tblgentables b WITH(NOLOCK) ON a.companytype = b.detno AND b.tablename = 'COMPANY TYPE'
	LEFT JOIN tblcompanycontractyears c WITH(NOLOCK) ON a.compcode = c.compcode
	WHERE a.compcode = @lcompcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_uploadmemgetencyptv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemgetencyptv2]
	-- Add the parameters for the stored procedure here
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	
    /****** Script for SelectTopNRows command from SSMS  ******/
SELECT a.portalcode as portalcode
	,batchcode = ISNULL(a.batchcode,0)
	,a.batchno
      ,b.portalno
      ,a.compcode
      ,a.contractcode
      ,b.withaffiliate
      ,b.prorated
      ,b.uploadtype
      ,b.statuscode
      ,b.filename
      ,b.remarks
      ,b.datetransferred
      ,b.datequeued
      ,b.datefinished
      ,b.datenotified
      ,b.dateencoded
      ,b.encodedby
      ,b.importedcodedummy
      ,b.seen
      ,b.notifymeonly
      ,b.notificationtype
      ,b.seekby
      ,b.uploaded
      ,b.duration
      ,b.percentage
      ,encodedbyname = IIF(hrportal <> 0, encodedbyname, ISNULL(LTRIM(RTRIM(e.username)),''))
	  ,encodedbyemail = ISNULL(LTRIM(RTRIM(e.emailadd)),'')
	  ,b.hrportal
	  ,b.partial
  FROM tblmemberuploadbatch a WITH(NOLOCK)
  LEFT JOIN  tblportalupload b WITH(NOLOCK) ON a.portalcode = b.portalcode
  LEFT JOIN tblusers e WITH(NOLOCK) ON b.encodedby = e.userno
  WHERE a.statuscode = 1 and a.retail = 0 and b.statuscode = 4 and b.datefinished = '01/01/1900'
  OPTION(RECOMPILE)


END
GO

-- ---- sp_uploadmemgetnewbenefitplansv2 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_uploadmemgetnewbenefitplansv2] --14
	-- Add the parameters for the stored procedure here
	
	@compcode		Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE	@lcompcode		Int		= @compcode
		
	SELECT plancode = 0, sobplancode = 0, a.classcode, planname = classname, a.contractcode, membertype = '', 
	ISNULL(a.effectivity, '1900-01-01') AS effectivity,
	ISNULL(a.expiry, '1900-01-01') AS expiry 
	FROM tblcompanyclasses a WITH(NOLOCK)
	--OUTER APPLY (SELECT compcode, contractcode, effectivity, expiry FROM tblcompanycontractyears b WITH(NOLOCK) WHERE a.compcode = b.compcode) AS b
	WHERE a.compcode = @lcompcode --AND approvedby <> 0
	OPTION(RECOMPILE)

END
GO

-- ---- sp_uploadmemgetnewpremiummembersv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_uploadmemgetnewpremiummembersv2] --57, 57
	-- Add the parameters for the stored procedure here
	@compcode		INT,
	@contractcode	INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	DECLARE @lcompcode		INT = @compcode,
			@lcontractcode	INT = @contractcode

	--Before 2021/01/18 Revision


	--SELECT
	--billclassdetno = a.detno,
	--a.premiumclasscode,
	--a.billingschedule,
	--perbilling= ISNULL(b.perbilling, 0),
	--allowprorated= ISNULL(b.allowprorated, 0),
	--premiumcode = ISNULL(b.premiumcode, 0),
	--feecode = ISNULL(b.feecode, 0),
	--sumassured = ISNULL(b.sumassured, 0.00),
	--membertype = ISNULL(c.membertype, ''),
	--agefrom = ISNULL(c.agefrom, 0),
	--ageto = ISNULL(c.ageto, 0),
	--feecategory = ISNULL(d.categcode, 0) 
	--FROM tblcompanyclassesbilling a
	--OUTER APPLY(SELECT compcode, contractcode, premiumcode, feecode, sumassured, perbilling, allowprorated FROM tblcompanypremiums b WHERE a.compcode = b.compcode AND a.contractcode = b.contractcode AND b.approvedby <> 0 AND a.detno = b.billclassdetno) b
	----OUTER APPLY(SELECT compcode, contractcode, premiumcode, feecode, sumassured, perbilling, allowprorated FROM tblcompanypremiums b WHERE a.compcode = b.compcode AND a.contractcode = b.contractcode AND a.detno = b.billclassdetno) b
	--OUTER APPLY(SELECT membertype, agefrom, ageto FROM tblcompanypremiummember c WHERE b.compcode = c.compcode AND b.contractcode = c.contractcode AND b.premiumcode = c.premiumcode) c
	--OUTER APPLY(SELECT categcode FROM tblfees d WHERE b.feecode = d.feecode) d
	--WHERE a.compcode = @lcompcode AND a.contractcode = @lcontractcode
	--OPTION(RECOMPILE)

	SELECT
	a.contractcode,
	billclassdetno = a.detno,
	a.premiumclasscode,
	a.billingschedule,
	perbilling= ISNULL(b.perbilling, 0),
	allowprorated= ISNULL(b.allowprorated, 0),
	premiumcode = ISNULL(b.premiumcode, 0),
	feecode = ISNULL(b.feecode, 0),
	premiumrate = ISNULL(c.premiumrate, 0.00),
	membertype = ISNULL(c.membertype, ''),
	agefrom = ISNULL(c.agefrom, 0),
	ageto = ISNULL(c.ageto, 0),
	feecategory = ISNULL(d.categcode, 0)
	,plancode = 0
	,premiumsetup = ISNULL(e.premiumsetup, 0)
	FROM tblcompanyclassesbilling a WITH(NOLOCK)
	LEFT JOIN tblcompanypremiums b WITH(NOLOCK) 
		ON a.compcode = b.compcode 
		AND a.contractcode = b.contractcode 
		AND b.approvedby <> 0 
		AND a.detno = b.billclassdetno
	--OUTER APPLY(SELECT compcode, contractcode, premiumcode, feecode, sumassured, perbilling, allowprorated FROM tblcompanypremiums b WHERE a.compcode = b.compcode AND a.contractcode = b.contractcode AND a.detno = b.billclassdetno) b
	LEFT JOIN tblcompanypremiummember c WITH(NOLOCK) 
		ON b.compcode = c.compcode 
		AND b.contractcode = c.contractcode 
		AND b.premiumcode = c.premiumcode
	LEFT JOIN tblfees d WITH(NOLOCK) 
		ON b.feecode = d.feecode
	LEFT JOIN tblsettingspremium e WITH(NOLOCK) 
		ON a.compcode = e.compcode 
		AND a.detno = e.billclassdetno
	--OUTER APPLY(SELECT plancode FROM tblcompanybenefitplan e WITH(NOLOCK) WHERE a.compcode = b.compcode) AS e
	WHERE a.compcode = @lcompcode AND a.contractcode = @lcontractcode and b.approvedby <> 0 AND b.extensioncode = 0
	OPTION(RECOMPILE)
END
GO

-- ---- sp_uploadmemgetnewreuploadedv2 ----
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_uploadmemgetnewreuploadedv2] --57, 57
	-- Add the parameters for the stored procedure here
	@compcode		INT,
	@contractcode	INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	DECLARE @lcompcode		INT = @compcode,
			@lcontractcode	INT = @contractcode

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	SET @SQL = N'SELECT DISTINCT membercode, contractcode
	FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberfees a WITH(NOLOCK)
	WHERE a.compcode = @lcompcode AND a.contractcode >= @lcontractcode AND cancelled = 0
	ORDER BY contractcode DESC
	OPTION(RECOMPILE)'

	EXEC master.sys.sp_executesql
	@SQL,
	N'@lcompcode INT, @lcontractcode INT',
	@lcompcode = @lcompcode,
	@lcontractcode = @lcontractcode

	--SELECT DISTINCT membercode, contractcode
	--FROM tblmemberfees a WITH(NOLOCK)
	--WHERE a.compcode = @lcompcode AND a.contractcode >= @lcontractcode AND cancelled = 0
	--ORDER BY contractcode DESC
	--OPTION(RECOMPILE)

END
GO

-- ---- sp_uploadmemgetpushemailnotificationemails ----
CREATE   PROCEDURE [dbo].[sp_uploadmemgetpushemailnotificationemails]
	-- Add the parameters for the stored procedure here
	
	@type	TINYINT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @ltype	TINYINT	= @type

	SELECT DISTINCT emailadd
	FROM tblpushemailnotification a WITH(NOLOCK)
	OUTER APPLY (SELECT userno, emailadd FROM tblusers b WITH(NOLOCK) WHERE a.userno = b.userno) b
	WHERE b.emailadd <> '' AND a.type = @ltype
	OPTION(RECOMPILE)

END
GO

-- ---- sp_uploadmemgetrenewalmembersv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_uploadmemgetrenewalmembersv2]
	@portalcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	INT = @portalcode,
			@lcompcode		INT = 0

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	SELECT @lcompcode = compcode
	FROM tblportalupload
	WHERE portalcode = @lportalcode
	
	EXEC sp_opensymmetric

    SET @SQL = N'SELECT
	a.membercode,
	membername = LTRIM(RTRIM('+QUOTENAME(@DBname)+'.dbo.decodercontains(a.mdflog, 0))),
	lastname = LTRIM(RTRIM('+QUOTENAME(@DBname)+'.dbo.decodercontains(a.llog, 0))),
	firstname = LTRIM(RTRIM('+QUOTENAME(@DBname)+'.dbo.decodercontains(a.flog, 0))),
	miname = LTRIM(RTRIM('+QUOTENAME(@DBname)+'.dbo.Decrypt(a.miname))),
	a.birthdate,
	a.coveredfrom,
	a.coveredto,
	a.effectivity,
	a.expiry,
	a.policydivision,
	a.statuscode,
	a.membercategory,
	a.benefitclass,
	a.premiumclass,
	a.classorder,
	a.principalcode,
	b.uploadtype,
	a.credittermto,
	a.inactivedate
	FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers a WITH(NOLOCK)
	LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b ON a.membercode = b.membercode 
	WHERE b.compcode = @lcompcode
	AND b.portalcode = @lportalcode
	AND b.membercode <> 0
	AND b.uploadtype = ''R-PD''
	OPTION(RECOMPILE)'

	EXEC master.sys.sp_executesql
	@SQL,
	N'@lcompcode INT, @lportalcode INT',
	@lcompcode = @lcompcode,
	@lportalcode = @lportalcode

	--SELECT
	--a.membercode,
	--membername = ISNULL(dbo.decodercontains(a.mdflog, 0), ''),
	--lastname = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.llog, 0), ''))),
	--firstname = LTRIM(RTRIM(ISNULL(dbo.decodercontains(a.flog, 0), ''))),
	--miname = LTRIM(RTRIM(ISNULL(CONVERT(VARCHAR(100), DECRYPTBYKEY(a.miname)), ''))),
	--a.birthdate,
	--a.coveredfrom,
	--a.coveredto,
	--a.effectivity,
	--a.expiry,
	--a.policydivision,
	--a.statuscode,
	--a.membercategory,
	--a.benefitclass,
	--a.premiumclass,
	--a.classorder,
	--a.principalcode,
	--b.uploadtype,
	--a.credittermto,
	--a.inactivedate
	--FROM tblmembers a WITH(NOLOCK)
	--OUTER APPLY (SELECT portalcode,membercode,uploadtype FROM tblportaluploaddetails b WHERE b.compcode = @lcompcode and a.membercode = b.membercode) b
	--WHERE b.portalcode = @lportalcode and b.membercode <> 0 and b.uploadtype = 'R-PD'
	--OPTION(RECOMPILE)
	
	EXEC sp_closesymmetric
END
GO

-- ---- sp_uploadmemgetterminationmembersv2 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_uploadmemgetterminationmembersv2]
	-- Add the parameters for the stored procedure here
	
	@compcode	Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lcompcode	Int	= @compcode

	EXEC sp_opensymmetric

	SELECT a.membercode, a.compcode, a.membertype, a.classorder, a.employeeno, a.memberno, a.suffix, a.birthdate, a.gender, a.civilstatus, a.effectivity, a.expiry, a.principalcode, a.relation, a.statuscode, a.inactivedate,
	lastname = dbo.Decrypt(a.lastname),
	firstname = dbo.Decrypt(a.firstname),
	miname = dbo.Decrypt(a.miname),
	mobile = dbo.Decrypt(ISNULL(b.mobile, '')),
	emailaddress = dbo.Decrypt(ISNULL(b.emailaddress, '')),
	occupation = ISNULL(b.occupation, ''),
	telephone = ISNULL(b.telephone, ''),
	officephone = ISNULL(b.officephone, ''),
	officefax = ISNULL(b.officefax, ''),
	tin = ISNULL(b.tin, '')
	FROM tblmembers a WITH(NOLOCK)
	LEFT JOIN tblmemberdetails b WITH(NOLOCK) ON a.compcode = b.compcode AND a.membercode = b.membercode
	WHERE a.compcode = @lcompcode
	OPTION(RECOMPILE)

	EXEC sp_closesymmetric

END
GO

-- ---- sp_uploadmemmapenrollmentperiodv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemmapenrollmentperiodv2]
	@portalcode		Int,
	@compcode		Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode		Int = @portalcode,
			@lcompcode			Int = @compcode
	
	UPDATE c SET
	enrollmentperiodfrom = a.enrollmentperiodfrom,
	enrollmentperiodto = a.enrollmentperiodto
	FROM tblportalupload a WITH(NOLOCK)
	LEFT JOIN tblportaluploaddetails b WITH(NOLOCK) ON a.portalcode = b.portalcode
	LEFT JOIN tblmembers c WITH(NOLOCK) ON a.compcode = c.compcode AND b.membercode = c.membercode
	WHERE a.compcode = @lcompcode AND a.portalcode = @lportalcode
	OPTION(RECOMPILE)

END
GO

-- ---- sp_uploadmemmapmemberdetailsv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemmapmemberdetailsv2]
	@portalcode		INT,
	@compcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode		INT = @portalcode,
			@lcompcode			INT = @compcode,
			@lwithnewmembers	BIT = 0
	
	SELECT @lwithnewmembers = withnewmembers FROM tblportalupload WHERE portalcode = @lportalcode

	IF @lwithnewmembers = 1
		BEGIN
			UPDATE b SET
			membercode = a.membercode,
			memberno = a.memberno,
			topupplan = ISNULL(c.topupplan, 0)
			FROM tblportaluploaddetails a WITH(NOLOCK)
			LEFT JOIN tblmemberdetails b WITH(NOLOCK) 
				ON a.compcode = b.compcode 
				AND a.dummymemberno = b.dummymemberno
	
			LEFT JOIN  tblcompanyclasses c WITH(NOLOCK) 
				ON a.compcode = c.compcode 
				AND a.contractcode = c.contractcode 
				AND a.benefitclass = c.classcode

			WHERE a.compcode = @lcompcode AND a.portalcode = @lportalcode AND a.uploadtype <> 'R-PD' AND a.uploadtype <> 'A-MP' AND a.uploadtype <> 'F-PD'
		END
END
GO

-- ---- sp_uploadmemmapmemberfeesv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemmapmemberfeesv2]
	@portalcode		INT,
	@compcode		INT,
	@contractcode	INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode		INT = @portalcode,
			@lcompcode			INT = @compcode,
			@lcontractcode		INT = @contractcode

	UPDATE b SET
	b.membercode = ISNULL(a.membercode, 0)
	FROM tblportaluploaddetails a WITH(NOLOCK)
	
	LEFT JOIN tblmemberfees b WITH(NOLOCK) 
	ON b.compcode = @lcompcode 
	AND b.contractcode = @lcontractcode
	AND a.dummymemberno = b.dummymemberno
	
	WHERE a.portalcode = @lportalcode
END
GO

-- ---- sp_uploadmemmapmembernov2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemmapmembernov2]
	@portalcode		INT,
	@compcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode		INT = @portalcode,
			@lcompcode			INT = @compcode,
			@lwithnewmembers	BIT = 0

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))
	
	SELECT @lwithnewmembers = withnewmembers FROM tblportalupload WHERE portalcode = @lportalcode

	IF @lwithnewmembers = 1
		BEGIN
			UPDATE b SET
			b.memberno = ISNULL(a.memberno, '')
			FROM tblportaluploaddetails a WITH(NOLOCK)
			LEFT JOIN tblmembers b WITH(NOLOCK) ON b.compcode = @lcompcode AND a.dummymemberno = b.dummymemberno
			WHERE a.portalcode = @lportalcode AND a.uploadtype <> 'R-PD' AND a.uploadtype <> 'A-MP'

			SET @SQL = 
			N'UPDATE a SET
			a.membercode = ISNULL(b.membercode, 0)
			FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
			LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK) 
			ON b.compcode = @lcompcode
			AND a.dummymemberno = b.dummymemberno
			
			WHERE a.portalcode = @lportalcode
				AND a.uploadtype <> ''R-PD'' 
				AND a.uploadtype <> ''A-MP'' 
				AND a.uploadtype <> ''F-PD''
			'

			--EXEC (@SQL)
			EXEC master.sys.sp_executesql
			@SQL,
			N'@lcompcode INT, @lportalcode INT',
			@lcompcode = @lcompcode,
			@lportalcode = @lportalcode

		END
END
GO

-- ---- sp_uploadmemmapmemberuploaddetailsv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemmapmemberuploaddetailsv2]
	@portalcode		INT,
	@compcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode		INT = @portalcode,
			@lcompcode			INT = @compcode

	UPDATE b SET
	b.membercode = ISNULL(a.membercode, 0),
	b.memberno = ISNULL(a.memberno, '')
	FROM tblportaluploaddetails a WITH(NOLOCK)
	OUTER APPLY (SELECT membercode, memberno FROM tblmemberuploaddetails b WITH(NOLOCK) WHERE b.compcode = @lcompcode AND a.dummymemberno = b.dummymemberno) b
	WHERE a.portalcode = @lportalcode

	--UPDATE a SET
	--a.membercode = ISNULL(b.membercode, 0),
	--a.memberno = ISNULL(b.memberno, '')
	--FROM tblmemberuploaddetails a WITH(NOLOCK)
	--LEFT JOIN tblportaluploaddetails b WITH(NOLOCK) ON b.portalcode = @lportalcode 
	--WHERE a.compcode = @lcompcode AND a.dummymemberno = b.dummymemberno 

END
GO

-- ---- sp_uploadmemmapprindepportaldetailsv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemmapprindepportaldetailsv2]
	@portalcode		INT,
	@compcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode		INT = @portalcode,
			@lcompcode			INT = @compcode,
			@lparentcompcode	INT = 0,
			@luploadtype		VARCHAR(20) = '',
			@lseekby			INT = 0,
			@lenhancedencryption	BIT	= 0

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	SELECT @luploadtype = uploadtype, @lseekby = seekby
	FROM tblportalupload WITH(NOLOCK)
	WHERE portalcode = @lportalcode
	
	SELECT @lparentcompcode = parentcompcode,  @lenhancedencryption = enhancedencryption FROM tblcompany WITH(NOLOCK) WHERE compcode = @lcompcode

	IF @lseekby = 2
	BEGIN
		IF @luploadtype = 'NR-DOP'
			BEGIN
				SET @SQL = 
				N'UPDATE a SET
				princivilstatus = c.civilstatus
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)

				OUTER APPLY (
					SELECT TOP 1 c.civilstatus
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames cc WITH(NOLOCK) 
						ON cc.membercode = c.membercode 
						AND @lenhancedencryption = 1					
					WHERE c.compcode = @lparentcompcode 
					AND c.classorder = 0 
					AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.llog ELSE c.llog END)) 
					AND a.pbirthdate = c.birthdate 
				) c
			 
				WHERE a.classorder = 1 
				AND a.portalcode = @lportalcode 
				AND a.uploadtype IN (''NR-DOP'', ''R-PD'')
				AND c.civilstatus IS NOT NULL
				AND a.princivilstatus <> c.civilstatus;
				'

				--EXEC (@SQL)
				EXEC master.sys.sp_executesql
				@SQL,
				N'@lparentcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
				@lparentcompcode = @lparentcompcode,
				@lenhancedencryption = @lenhancedencryption,
				@lportalcode = @lportalcode
			END

		IF @luploadtype = 'NR-PD'
			BEGIN
				SET @SQL = 
				N'UPDATE a SET
				principalcode = IIF((c.membercode = 0 OR c.membercode IS NULL), ISNULL(b.detno, a.principalcode), c.membercode),
				princivilstatus = ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				
				OUTER APPLY (
					SELECT TOP 1 b.detno, b.civilstatus FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK) 
					WHERE b.compcode = @lcompcode 
					AND b.classorder = 0 
					AND RTRIM(UPPER(a.pllog))= RTRIM(UPPER(b.llog)) 
					AND a.pbirthdate = b.birthdate
				) b

				OUTER APPLY (
					SELECT TOP 1 c.membercode, c.civilstatus
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames cc WITH(NOLOCK) 
						ON cc.membercode = c.membercode 
						AND @lenhancedencryption = 1					
					WHERE c.compcode = @lcompcode 
					AND c.classorder = 0 
					AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.llog ELSE c.llog END)) 
					AND a.pbirthdate = c.birthdate 
				) c

				WHERE a.classorder = 1 
				AND a.portalcode = @lportalcode 
				AND a.uploadtype IN (''N-PD'', ''R-PD'')
				AND (a.principalcode <> IIF((c.membercode = 0 OR c.membercode IS NULL), ISNULL(b.detno, a.principalcode), c.membercode)
					OR a.princivilstatus <> ISNULL(c.civilstatus, ISNULL(b.civilstatus, '''')))

				'


				--EXEC (@SQL)
				EXEC master.sys.sp_executesql
				@SQL,
				N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
				@lcompcode = @lcompcode,
				@lenhancedencryption = @lenhancedencryption,
				@lportalcode = @lportalcode
			END

		IF @luploadtype = 'M-PD'
			BEGIN
				
				SET @SQL = 
				N'UPDATE a SET
				principalcode = IIF(ISNULL(c.membercode, 0) = 0, ISNULL(b.detno, a.principalcode), ISNULL(c.membercode, 0)),
				princivilstatus = ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				
				OUTER APPLY (
					SELECT TOP 1 b.detno, b.civilstatus FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK) 
					WHERE b.compcode = @lcompcode 
					AND b.classorder = 0 
					AND RTRIM(UPPER(a.pllog))= RTRIM(UPPER(b.llog)) 
					AND a.pbirthdate = b.birthdate
				) b

				OUTER APPLY (
					SELECT TOP 1 c.membercode, c.civilstatus
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames cc WITH(NOLOCK) 
						ON cc.membercode = c.membercode 
						AND @lenhancedencryption = 1					
					WHERE c.compcode = @lcompcode 
					AND c.classorder = 0 
					AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.llog ELSE c.llog END)) 
					AND a.pbirthdate = c.birthdate 
				) c

				WHERE a.classorder = 1 AND a.portalcode = @lportalcode AND a.uploadtype = ''M-PD''
				AND (a.principalcode <> IIF(ISNULL(c.membercode, 0) = 0, ISNULL(b.detno, a.principalcode), ISNULL(c.membercode, 0)) 
					OR a.princivilstatus <> ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))) 
				'

				--EXEC (@SQL)
				EXEC master.sys.sp_executesql
				@SQL,
				N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
				@lcompcode = @lcompcode,
				@lenhancedencryption = @lenhancedencryption,
				@lportalcode = @lportalcode
			END

		IF @luploadtype = 'R-NR-PD'
			BEGIN
				SET @SQL = 
				N'UPDATE a SET
				principalcode = IIF(ISNULL(c.membercode, 0) = 0, ISNULL(b.detno, a.principalcode), ISNULL(c.membercode, 0)),
				princivilstatus = ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				
				OUTER APPLY (
					SELECT TOP 1 b.detno, b.civilstatus FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK) 
					WHERE b.compcode = @lcompcode 
					AND b.classorder = 0 
					AND RTRIM(UPPER(a.pllog))= RTRIM(UPPER(b.llog)) 
					AND a.pbirthdate = b.birthdate
				) b

				OUTER APPLY (
					SELECT TOP 1 c.membercode, c.civilstatus
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames cc WITH(NOLOCK) 
						ON cc.membercode = c.membercode 
						AND @lenhancedencryption = 1					
					WHERE c.compcode = @lcompcode 
					AND c.classorder = 0 
					AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.llog ELSE c.llog END)) 
					AND a.pbirthdate = c.birthdate 
					AND a.effectivity = c.effectivity
				) c

				WHERE a.classorder = 1 AND a.portalcode = @lportalcode AND a.uploadtype = ''R-NR-PD''
				AND (a.principalcode <> IIF(ISNULL(c.membercode, 0) = 0, ISNULL(b.detno, a.principalcode), ISNULL(c.membercode, 0)) 
					OR a.princivilstatus <> ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))) 
				'

				--EXEC (@SQL)
				EXEC master.sys.sp_executesql
				@SQL,
				N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
				@lcompcode = @lcompcode,
				@lenhancedencryption = @lenhancedencryption,
				@lportalcode = @lportalcode
			END
	END

	ELSE
	BEGIN
		IF @luploadtype = 'NR-DOP'
			BEGIN
				SET @SQL = 
				N'UPDATE a SET
				princivilstatus = c.civilstatus
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				
				
				OUTER APPLY (
					SELECT TOP 1 c.civilstatus
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames cc WITH(NOLOCK) 
						ON cc.membercode = c.membercode 
						AND @lenhancedencryption = 1					
					WHERE c.compcode = @lcompcode 
					AND c.classorder = 0 
					AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.llog ELSE c.llog END)) 
					AND RTRIM(UPPER(a.pflog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.flog ELSE c.flog END)) 
					AND a.pbirthdate = c.birthdate 
				) c
			 
				WHERE a.classorder = 1 
				AND a.portalcode = @lportalcode 
				AND a.uploadtype IN (''NR-DOP'', ''R-PD'')
				AND c.civilstatus IS NOT NULL
				AND a.princivilstatus <> c.civilstatus;
				'

				--EXEC (@SQL)
				EXEC master.sys.sp_executesql
				@SQL,
				N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
				@lcompcode = @lcompcode,
				@lenhancedencryption = @lenhancedencryption,
				@lportalcode = @lportalcode
			END

		IF @luploadtype = 'NR-PD'
			BEGIN
				SET @SQL = 
				N'UPDATE a SET
				principalcode = IIF((c.membercode = 0 OR c.membercode IS NULL), ISNULL(b.detno, a.principalcode), c.membercode),
				princivilstatus = ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				
				OUTER APPLY (
					SELECT TOP 1 b.detno, b.civilstatus FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK) 
					WHERE b.compcode = @lcompcode 
					AND b.classorder = 0 
					AND RTRIM(UPPER(a.pllog))= RTRIM(UPPER(b.llog)) 
					AND RTRIM(UPPER(a.pflog))= RTRIM(UPPER(b.flog)) 
					AND a.pbirthdate = b.birthdate
				) b

				OUTER APPLY (
					SELECT TOP 1 c.membercode, c.civilstatus
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames cc WITH(NOLOCK) 
						ON cc.membercode = c.membercode 
						AND @lenhancedencryption = 1					
					WHERE c.compcode = @lcompcode 
					AND c.classorder = 0 
					AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.llog ELSE c.llog END)) 
					AND RTRIM(UPPER(a.pflog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.flog ELSE c.flog END)) 
					AND a.pbirthdate = c.birthdate 
				) c

				WHERE a.classorder = 1 
				AND a.portalcode = @lportalcode 
				AND a.uploadtype IN (''N-PD'', ''R-PD'')
				AND (a.principalcode <> IIF((c.membercode = 0 OR c.membercode IS NULL), ISNULL(b.detno, a.principalcode), c.membercode)
					OR a.princivilstatus <> ISNULL(c.civilstatus, ISNULL(b.civilstatus, '''')))

				'
				
				--EXEC (@SQL)
				EXEC master.sys.sp_executesql
				@SQL,
				N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
				@lcompcode = @lcompcode,
				@lenhancedencryption = @lenhancedencryption,
				@lportalcode = @lportalcode
			END

		IF @luploadtype = 'M-PD'
			BEGIN
				SET @SQL = 
				N'UPDATE a SET
				principalcode = IIF(ISNULL(c.membercode, 0) = 0, ISNULL(b.detno, a.principalcode), ISNULL(c.membercode, 0)),
				princivilstatus = ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				
				OUTER APPLY (
					SELECT TOP 1 b.detno, b.civilstatus FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK) 
					WHERE b.compcode = @lcompcode 
					AND b.classorder = 0 
					AND RTRIM(UPPER(a.pllog))= RTRIM(UPPER(b.llog)) 
					AND RTRIM(UPPER(a.pflog))= RTRIM(UPPER(b.flog)) 
					AND a.pbirthdate = b.birthdate
				) b

				OUTER APPLY (
					SELECT TOP 1 c.membercode, c.civilstatus
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames cc WITH(NOLOCK) 
						ON cc.membercode = c.membercode 
						AND @lenhancedencryption = 1					
					WHERE c.compcode = @lcompcode 
					AND c.classorder = 0 
					AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.llog ELSE c.llog END)) 
					AND RTRIM(UPPER(a.pflog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.flog ELSE c.flog END)) 
					AND a.pbirthdate = c.birthdate
				) c

				WHERE a.classorder = 1 AND a.portalcode = @lportalcode AND a.uploadtype = ''M-PD''
				AND (a.principalcode <> IIF(ISNULL(c.membercode, 0) = 0, ISNULL(b.detno, a.principalcode), ISNULL(c.membercode, 0)) 
					OR a.princivilstatus <> ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))) 
				'

				--EXEC (@SQL)
				EXEC master.sys.sp_executesql
				@SQL,
				N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
				@lcompcode = @lcompcode,
				@lenhancedencryption = @lenhancedencryption,
				@lportalcode = @lportalcode
			END

		IF @luploadtype = 'R-NR-PD'
			BEGIN
				SET @SQL = 
				N'UPDATE a SET
				principalcode = IIF(ISNULL(c.membercode, 0) = 0, ISNULL(b.detno, a.principalcode), ISNULL(c.membercode, 0)),
				princivilstatus = ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))
				FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
				
				OUTER APPLY (
					SELECT TOP 1 b.detno, b.civilstatus FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails b WITH(NOLOCK) 
					WHERE b.compcode = @lcompcode 
					AND b.classorder = 0 
					AND RTRIM(UPPER(a.pllog))= RTRIM(UPPER(b.llog)) 
					AND RTRIM(UPPER(a.pflog))= RTRIM(UPPER(b.flog)) 
					AND a.pbirthdate = b.birthdate
				) b
				OUTER APPLY (
					SELECT TOP 1 c.membercode, c.civilstatus
					FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) 
					LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembernames cc WITH(NOLOCK) 
						ON cc.membercode = c.membercode 
						AND @lenhancedencryption = 1					
					WHERE c.compcode = @lcompcode 
					AND c.classorder = 0 
					AND RTRIM(UPPER(a.pllog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.llog ELSE c.llog END)) 
					AND RTRIM(UPPER(a.pflog)) = RTRIM(UPPER(CASE WHEN @lenhancedencryption = 1 THEN cc.flog ELSE c.flog END)) 
					AND a.pbirthdate = c.birthdate 
					AND a.effectivity = c.effectivity
				) c

				WHERE a.classorder = 1 AND a.portalcode = @lportalcode AND a.uploadtype = ''R-NR-PD''
				AND (a.principalcode <> IIF(ISNULL(c.membercode, 0) = 0, ISNULL(b.detno, a.principalcode), ISNULL(c.membercode, 0)) 
					OR a.princivilstatus <> ISNULL(c.civilstatus, ISNULL(b.civilstatus, ''''))) 
				'

				--EXEC (@SQL)
				EXEC master.sys.sp_executesql
				@SQL,
				N'@lcompcode INT, @lenhancedencryption BIT, @lportalcode INT',
				@lcompcode = @lcompcode,
				@lenhancedencryption = @lenhancedencryption,
				@lportalcode = @lportalcode
			END
	END


		
END
GO

-- ---- sp_uploadmemmapprindepv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemmapprindepv2]
	@portalcode		INT,
	@compcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode		INT = @portalcode,
			@lcompcode			INT = @compcode,
			@lparentcompcode	INT = 0,
			@luploadtype	VARCHAR(20) = ''

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	SELECT @luploadtype = uploadtype
	FROM tblportalupload
	WHERE portalcode = @lportalcode
	
	SELECT @lparentcompcode = parentcompcode FROM tblcompany WHERE compcode = @lcompcode

	IF @luploadtype = 'NR-DOP'
		BEGIN
			SET @SQL = N'UPDATE b SET
			b.principalcode = ISNULL(c.membercode, b.principalcode)
			FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
			LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK) ON b.compcode = @lcompcode AND a.membercode = b.membercode
			LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) ON c.compcode = @lparentcompcode AND c.classorder = 0 AND RTRIM(UPPER(b.pllog)) = RTRIM(UPPER(c.llog)) AND RTRIM(UPPER(b.pflog)) = RTRIM(UPPER(c.flog)) AND a.pbirthdate = c.birthdate
			WHERE a.portalcode = @lportalcode AND a.uploadtype = ''NR-DOP'' AND a.classorder = 1'

			EXEC master.sys.sp_executesql
			@SQL,
			N'@lcompcode INT, @lportalcode INT, @lparentcompcode INT',
			@lcompcode = @lcompcode,
			@lportalcode = @lportalcode,
			@lparentcompcode = @lparentcompcode

		END

	IF @luploadtype = 'NR-PD'
		BEGIN

			SET @SQL = N'UPDATE b SET
			b.principalcode = ISNULL(c.membercode, b.principalcode)
			FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
			LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK) ON b.compcode = @lcompcode AND a.membercode = b.membercode
			LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) ON c.compcode = @lcompcode AND c.classorder = 0 AND RTRIM(UPPER(b.pllog))= RTRIM(UPPER(c.llog)) and RTRIM(UPPER(b.pflog)) = RTRIM(UPPER(c.flog)) AND a.pbirthdate = c.birthdate
			WHERE a.portalcode = @lportalcode AND a.uploadtype = ''N-PD'' AND a.classorder = 1'

			EXEC master.sys.sp_executesql
			@SQL,
			N'@lcompcode INT, @lportalcode INT',
			@lcompcode = @lcompcode,
			@lportalcode = @lportalcode
		END

	IF @luploadtype = 'M-PD'
	BEGIN

		SET @SQL = N'UPDATE b SET
		b.principalcode = ISNULL(c.membercode, b.principalcode)
		FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
		LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK) ON b.compcode = @lcompcode AND a.membercode = b.membercode
		LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) ON c.compcode = @lcompcode AND c.classorder = 0 AND RTRIM(UPPER(b.pllog))= RTRIM(UPPER(c.llog)) and RTRIM(UPPER(b.pflog)) = RTRIM(UPPER(c.flog)) AND a.pbirthdate = c.birthdate
		WHERE a.portalcode = @lportalcode AND a.uploadtype = ''M-PD'' AND a.classorder = 1'

		EXEC master.sys.sp_executesql
		@SQL,
		N'@lcompcode INT, @lportalcode INT',
		@lcompcode = @lcompcode,
		@lportalcode = @lportalcode
	END

	IF @luploadtype = 'R-NR-PD'
	BEGIN
			
		SET @SQL = N'UPDATE b SET
		b.principalcode = ISNULL(c.membercode, b.principalcode)
		FROM '+QUOTENAME(@DBname)+'.dbo.tblportaluploaddetails a WITH(NOLOCK)
		LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b WITH(NOLOCK) WHERE b.compcode = @lcompcode AND a.membercode = b.membercode
		LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers c WITH(NOLOCK) WHERE c.compcode = @lcompcode AND c.classorder = 0 AND RTRIM(UPPER(b.pllog))= RTRIM(UPPER(c.llog)) and RTRIM(UPPER(b.pflog)) = RTRIM(UPPER(c.flog)) AND a.pbirthdate = c.birthdate
		WHERE a.portalcode = @lportalcode AND a.uploadtype = ''R-NR-PD'' AND a.classorder = 1'

		EXEC master.sys.sp_executesql
		@SQL,
		N'@lcompcode INT, @lportalcode INT',
		@lcompcode = @lcompcode,
		@lportalcode = @lportalcode
	END


		
END
GO

-- ---- sp_uploadmemsavemembernamesv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemsavemembernamesv2]
	@portalcode		INT,
	@compcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode		INT = @portalcode,
			@lcompcode			INT = @compcode,
			@lenhancedencrypt	Bit = 0

	
	SELECT @lenhancedencrypt = enhancedencryption FROM tblcompany WHERE compcode = @lcompcode

	IF @lenhancedencrypt = 1
	BEGIN
		IF OBJECT_ID('tempdb..#temp_membernames') IS NOT NULL 
		BEGIN 
			DROP TABLE #temp_membernames
		END

		CREATE TABLE #temp_membernames
		(
			membercode		Int,
			memberno		Varchar(30),
			membername		Varchar(240),
			firstname		Varchar(240),
			lastname		Varchar(240),
			miname			Varchar(240),
			suffix			Varchar(20),
			birthdate		Smalldatetime,
			mdflog			Varchar(100),
			llog			Varchar(100),
			flog			Varchar(100),
			principalcode	Int,
			pllog			Varchar(100),
			pflog			Varchar(100),
			pmemberno		Varchar(30),
			pbirthdate		Smalldatetime,
		)

	
		EXEC sp_opensymmetric
		--INSERT TO TEMP TABLE
		INSERT INTO #temp_membernames (membercode, memberno, membername, firstname, lastname, miname, suffix, birthdate,
										mdflog, llog, flog, 
										principalcode, pllog, pflog)
		SELECT a.membercode, a.memberno, dbo.Decrypt(a.membername), dbo.Decrypt(a.firstname), dbo.Decrypt(a.lastname), dbo.Decrypt(a.miname), a.suffix, a.birthdate,
				dbo.decodercontains(a.mdflog, 0), dbo.decodercontains(a.llog, 0), dbo.decodercontains(a.flog, 0), 
				a.principalcode, dbo.decodercontains(a.pllog, 0), dbo.decodercontains(a.pflog, 0)
		FROM tblmembers a WITH(NOLOCK)
		LEFT JOIN tblportaluploaddetails b WITH(NOLOCK) ON a.membercode = b.membercode
		WHERE b.portalcode = @lportalcode AND b.uploadtype <> 'R-PD' AND b.uploadtype <> 'A-MP' AND b.uploadtype <> 'F-PD'

		EXEC sp_closesymmetric

		EXEC sp_opensymmetriccompany
		--INSERT TO tblmembernames
		INSERT INTO tblmembernames(membercode, membername, firstname, lastname, miname, suffix, 
									mdflog, llog, flog, pllog, pflog)
		SELECT a.membercode, dbo.EncryptCompany(a.membername), dbo.EncryptCompany(a.firstname), dbo.EncryptCompany(a.lastname), dbo.EncryptCompany(a.miname), dbo.EncryptCompany(a.suffix), 
		dbo.decodercontains(a.mdflog, 1), dbo.decodercontains(a.llog, 1), dbo.decodercontains(a.flog, 1), dbo.decodercontains(a.pllog, 1), dbo.decodercontains(a.pflog, 1)
		FROM #temp_membernames a

		EXEC sp_closesymmetriccompany

		--GET PRINCIPAL DETAILS
		EXEC sp_opensymmetric
		UPDATE a SET
			pmemberno = ISNULL(b.memberno, ''),
			pbirthdate = ISNULL(b.birthdate, '1/1/1900')
		FROM #temp_membernames a WITH(NOLOCK)
		LEFT JOIN tblmembers b WITH(NOLOCK) ON a.principalcode = b.membercode

		UPDATE #temp_membernames SET
			firstname = dbo.Encrypt(memberno + ',' + CONVERT(VARCHAR(10), birthdate, 104)),
			lastname = dbo.Encrypt(LEFT(lastname, 3)),
			membername = dbo.Encrypt(LEFT(lastname, 3) + ',' + memberno + ',' + CONVERT(VARCHAR(10), birthdate, 104)),
			flog = dbo.decodercontains(memberno + ',' + CONVERT(VARCHAR(10), birthdate, 104), 1),
			llog = dbo.decodercontains(LEFT(lastname, 3), 1),
			mdflog = dbo.decodercontains(LEFT(lastname, 3) + ',' + memberno + ',' + CONVERT(VARCHAR(10), birthdate, 104), 1),
			pflog = dbo.decodercontains(pmemberno + ',' + CONVERT(VARCHAR(10), pbirthdate, 104), 1),
			pllog = dbo.decodercontains(LEFT(pllog, 3), 1)

		--UPDATE MEMBER
		--UPDATE a SET
		--	firstname = dbo.Encrypt(b.memberno + ',' + CONVERT(VARCHAR(10), b.birthdate, 104)),
		--	lastname = dbo.Encrypt(LEFT(b.lastname, 3)),
		--	flog = dbo.decodercontains(b.memberno + ',' + CONVERT(VARCHAR(10), b.birthdate, 104), 1),
		--	llog = dbo.decodercontains(LEFT(b.lastname, 3), 1),
		--	pflog = dbo.decodercontains(b.pmemberno + ',' + CONVERT(VARCHAR(10), b.pbirthdate, 104), 1),
		--	pllog = dbo.decodercontains(LEFT(b.pllog, 3), 1)
		--FROM tblmembers a WITH(NOLOCK)
		--OUTER APPLY (SELECT memberno, firstname, lastname, birthdate, llog, flog, pmemberno, pbirthdate, pllog, pflog FROM #temp_membernames b WITH(NOLOCK) WHERE a.membercode = b.membercode) b
		
		UPDATE b SET
		b.firstname = a.firstname,
		b.lastname = a.lastname,
		b.membername = a.membername,
		b.flog = a.flog,
		b.llog = a.llog,
		b.mdflog = a.mdflog,
		b.pflog = a.pflog,
		b.pllog = a.pllog
		FROM #temp_membernames a WITH(NOLOCK)
		LEFT JOIN  tblmembers b WITH(NOLOCK) ON a.membercode = b.membercode
		EXEC sp_closesymmetric

		DROP TABLE #temp_membernames
	END	
END
GO

-- ---- sp_uploadmemsaveportaluploaddetails ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_uploadmemsaveportaluploaddetails]
	-- Add the parameters for the stored procedure here
	@portalcode	Int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	Int = @portalcode

	CREATE TABLE #temp_autorenewalmembers
    (
        portalcode     INT,
        portalno       VARCHAR(50),
        compcode       INT,
        contractcode   INT,
        membercode     INT,
        uploadtype     VARCHAR(20)
    )

    CREATE TABLE #temp_principals
    (
        membercode INT PRIMARY KEY
    )

    SELECT
        a.portalcode,
        a.portalno,
        a.compcode,
        a.contractcode,
        a.uploadtype,
        b.effectivity,
        b.expiry
    INTO #temp_portal
    FROM tblportalupload a
    INNER JOIN tblcompanycontractyears b
        ON a.contractcode = b.contractcode
    WHERE a.portalcode = @lportalcode
        AND a.autorenewal <> ''

    SELECT
        b.compcode,
        b.membercode,
        b.principalcode,
        b.classorder,
        b.statuscode,
        b.effectivity,
        b.expiry
    INTO #temp_members
    FROM tblportalupload a
    INNER JOIN tblmembers b
        ON a.compcode = b.compcode
    WHERE a.portalcode = @lportalcode
        AND a.autorenewal <> ''
        AND b.statuscode IN (1,2,6)

    -------------------------------------------------
    -- NR-PD PRINCIPALS
    -------------------------------------------------
    INSERT INTO #temp_autorenewalmembers
    (
        portalcode,
        portalno,
        compcode,
        contractcode,
        membercode,
        uploadtype
    )
    SELECT
        p.portalcode,
        p.portalno,
        p.compcode,
        p.contractcode,
        m.membercode,
        p.uploadtype
    FROM #temp_portal p
    INNER JOIN #temp_members m
        ON m.expiry = DATEADD(DAY, -1, p.effectivity)
        AND m.classorder = 0
    WHERE p.uploadtype = 'NR-PD'

    -------------------------------------------------
    -- NR-PD DEPENDENTS
    -------------------------------------------------
    INSERT INTO #temp_autorenewalmembers
    (
        portalcode,
        portalno,
        compcode,
        contractcode,
        membercode,
        uploadtype
    )
    SELECT
        p.portalcode,
        p.portalno,
        p.compcode,
        p.contractcode,
        m.membercode,
        p.uploadtype
    FROM #temp_portal p
    INNER JOIN #temp_members m
        ON m.expiry = DATEADD(DAY, -1, p.effectivity)
        AND m.classorder = 1
        AND m.principalcode <> 0
    WHERE p.uploadtype = 'NR-PD'
    AND (EXISTS
    (
        SELECT 1
        FROM #temp_autorenewalmembers t
        WHERE t.portalcode = p.portalcode
            AND t.membercode = m.principalcode
    )
    OR EXISTS
    (
        SELECT 1
        FROM #temp_members x
        WHERE x.membercode = m.principalcode
        AND x.classorder = 0
        AND x.effectivity = DATEADD(DAY, 1, m.expiry)
    ))

    -------------------------------------------------
    -- NR-D DEPENDENTS
    -------------------------------------------------
    INSERT INTO #temp_autorenewalmembers
    (
        portalcode,
        portalno,
        compcode,
        contractcode,
        membercode,
        uploadtype
    )
    SELECT
        p.portalcode,
        p.portalno,
        p.compcode,
        p.contractcode,
        m.membercode,
        p.uploadtype
    FROM #temp_portal p
    INNER JOIN #temp_members m
        ON m.expiry = DATEADD(DAY, -1, p.effectivity)
        AND m.classorder = 1
        AND m.principalcode = 0
    WHERE p.uploadtype = 'NR-D'

    -------------------------------------------------
    -- NR-DOP PRINCIPALS
    -------------------------------------------------
    INSERT INTO #temp_principals
    (
        membercode
    )
    SELECT m.membercode
    FROM #temp_portal p
    INNER JOIN #temp_members m
        ON m.expiry = DATEADD(DAY, -1, p.effectivity)
        AND m.classorder = 0
    WHERE p.uploadtype = 'NR-DOP'

    -------------------------------------------------
    -- NR-DOP DEPENDENTS
    -------------------------------------------------
    INSERT INTO #temp_autorenewalmembers
    (
        portalcode,
        portalno,
        compcode,
        contractcode,
        membercode,
        uploadtype
    )
    SELECT
        p.portalcode,
        p.portalno,
        p.compcode,
        p.contractcode,
        m.membercode,
        p.uploadtype
    FROM #temp_portal p
    INNER JOIN #temp_members m
        ON m.expiry = DATEADD(DAY, -1, p.effectivity)
        AND m.classorder = 1
        AND m.principalcode <> 0
    WHERE p.uploadtype = 'NR-DOP'
    AND NOT EXISTS
    (
        SELECT 1
        FROM #temp_principals tp
        WHERE tp.membercode = m.principalcode
    )

    -------------------------------------------------
    -- INSERT TO tblportaluploaddetails
    -------------------------------------------------

    EXEC sp_opensymmetric

    INSERT INTO tblportaluploaddetails
    (
        portalcode,
        uploadtype,
        rowno,
        importedcode,
        compcode,
        contractcode,
        membertype,
        classification,
        employeeno,
        benefitclass,
        premiumclass,
        lastname,
        firstname,
        miname,
        suffix,
        membername,
        birthdate,
        gender,
        civilstatusdesc,
        plname,
        pfname,
        pbirthdate,
        effectivity,
        expiry,
        viptagging,
        dummymemberno,
        classorder,
        civilstatus,
        billingschedule,
        billclassdetno,
        coveredfrom,
        coveredto,
        statuscode,
        mname,
        pmname,
        dependentcoveragetype
    )
    SELECT
        a.portalcode,
        a.uploadtype,
        ROW_NUMBER() OVER
        (
            PARTITION BY a.portalcode
            ORDER BY b.membercode
        ) + 1,
        a.portalno,
        a.compcode,
        a.contractcode,
        TRIM(b.membercategory),
        IIF(b.classorder = 0, 'P', 'D'),
        b.employeeno,
        b.benefitclass,
        b.premiumclass,
        dbo.Decrypt(b.lastname),
        dbo.Decrypt(b.firstname),
        dbo.Decrypt(b.miname),
        b.suffix,
        dbo.Decrypt(b.membername),
        b.birthdate,
        b.gender,
        d.description,
        ISNULL(dbo.Decrypt(e.lastname), ''),
        ISNULL(dbo.Decrypt(e.firstname), ''),
        ISNULL(e.birthdate, '19000101'),
        g.effectivity,
        g.expiry,
        IIF(ISNULL(c.vip, 0) = 0, 'False', 'True'),
        b.dummymemberno,
        b.classorder,
        b.civilstatus,
        b.billingschedule,
        ISNULL(f.detno, 0),
        b.coveredfrom,
        b.coveredto,
        statuscode = IIF(g.effectivity < GETDATE() AND g.effectivity + g.renewalcreditterm > GETDATE(), 1, 2),
        dbo.Decrypt(b.membername),
        ISNULL(dbo.Decrypt(e.membername), ''),
        ISNULL(c.dependentcoveragetype, 0)
    FROM #temp_autorenewalmembers a
    LEFT JOIN tblmembers b
        ON a.compcode = b.compcode
        AND a.membercode = b.membercode
    LEFT JOIN tblmemberdetails c
        ON a.compcode = c.compcode
        AND b.membercode = c.membercode
    LEFT JOIN tblgentables d
        ON d.tablename = 'CIVILSTATUS'
        AND b.civilstatus = d.recordno
    LEFT JOIN tblmembers e
        ON b.principalcode = e.membercode
        AND b.principalcode <> 0
    LEFT JOIN tblcompanyclassesbilling f
        ON a.compcode = f.compcode
        AND a.contractcode = f.contractcode
        AND b.premiumclass = f.premiumclasscode
    LEFT JOIN tblcompanycontractyears g
        ON a.contractcode = g.contractcode
    WHERE a.portalcode = @lportalcode

    UPDATE a
    SET uploaded = (SELECT COUNT(*) FROM tblportaluploaddetails b WHERE b.portalcode = a.portalcode)
    FROM tblportalupload a
    WHERE a.portalcode = @lportalcode;

    EXEC sp_closesymmetric

    DROP TABLE #temp_autorenewalmembers
    DROP TABLE #temp_principals
    DROP TABLE #temp_portal
    DROP TABLE #temp_members

END
GO

-- ---- sp_uploadmemsavesoaaccountdetailspremiumv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemsavesoaaccountdetailspremiumv2]
	-- Add the parameters for the stored procedure here
	
	@compcode		Int,
	@contractcode	Int,
	@batchcode		Int,
	@approvedby		Int,
	@fromwebagent	Tinyint = 0
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lcompcode		Int				= @compcode,
			@lcontractcode	Int				= @contractcode,
			@lbatchcode		Int				= @batchcode,
			@lsummarycode	Int				= 0,
			@lportalcode	Int				= 0,
			@lmemberpremium	Int				= 0,
			@lfromwebagent	Tinyint			= @fromwebagent,
			@luploadtype	VARCHAR(20)		= '',
			@lbatchtype		VARCHAR(20)		= ''

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(20)		= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

	SELECT
	@lbatchtype = RTRIM(UPPER(batchtype)),
	@luploadtype = RTRIM(UPPER(uploadsetup))
	FROM tblmemberuploadbatch 
	WHERE batchcode = @lbatchcode
	
	SET @lsummarycode = (SELECT summarycode FROM tblsoaaccountsummary WHERE compcode = @lcompcode AND batchcode = @lbatchcode)

	IF @lfromwebagent = 1
	BEGIN
		
		--SET @SQL = 'INSERT INTO tblsoaaccountsummarydetail(summarycode,memberfeecode,compcode,contractcode,billclassdetno,premiumcode,feecode,membercode,batchcode
		--	,active,cancelled,billingschedule,modalfactor,annualamount,amount,amountprorate,effectivity,modalfrom,modalto,monthused,monthcovered,soacode,soano
		--	,dummymemberno,dateencoded,encodedby,premiumclass)
		--SELECT '+CONVERT(VARCHAR(20), @lsummarycode)+',a.memberfeecode,a.compcode,a.contractcode,a.billclassdetno,a.premiumcode,a.feecode,a.membercode,a.batchcode,a.active,a.cancelled
		--	,a.billingschedule,a.modalfactor,a.annualamount,
		--	a.amount - ISNULL(c.amount, 0),
		--	a.amountprorate - ISNULL(c.amountprorate, 0),
		--	a.effectivity,a.modalfrom,a.modalto,a.monthused,a.monthcovered,a.soacode,a.soano
		--	,a.dummymemberno,a.dateencoded,a.encodedby,a.premiumclass
		--FROM '+@DBname+'.dbo.tblmemberfees a WITH(NOLOCK)
		--OUTER APPLY(SELECT compcode, membercode, membercategory, effectivity, modalfrom, modalto,waived FROM tblmemberuploaddetails b WITH(NOLOCK) WHERE b.compcode = a.compcode AND a.batchcode = b.batchcode AND a.membercode = b.membercode and b.waived = 0) b
		--OUTER APPLY(SELECT amount, amountprorate FROM '+@DBname+'.dbo.tblmemberfees c WITH(NOLOCK) WHERE a.compcode = c.compcode AND a.contractcode = c.contractcode AND a.batchcode <> c.batchcode AND a.feecode = c.feecode AND a.membercode = c.membercode AND c.active = 1 AND c.cancelled = 0) c
		--OUTER APPLY(SELECT batchtype FROM tblmemberuploadbatch d WITH(NOLOCK) WHERE a.batchcode = d.batchcode) d
		--WHERE a.compcode = '+CONVERT(VARCHAR(20), @lcompcode)+'  AND a.contractcode = '+CONVERT(VARCHAR(20), @lcontractcode)+' AND a.batchcode = '+CONVERT(VARCHAR(20), @lbatchcode)+' AND a.active = 1
		--OPTION(RECOMPILE)'

		--EXEC (@SQL)

		INSERT INTO tblsoaaccountsummarydetail(summarycode,memberfeecode,compcode,contractcode,billclassdetno,premiumcode,feecode,membercode,batchcode
			,active,cancelled,billingschedule,modalfactor,annualamount,amount,amountprorate,effectivity,modalfrom,modalto,monthused,monthcovered,soacode,soano
			,dummymemberno,dateencoded,encodedby,premiumclass)
		SELECT @lsummarycode,a.memberfeecode,a.compcode,a.contractcode,a.billclassdetno,a.premiumcode,a.feecode,a.membercode,a.batchcode,a.active,a.cancelled
			,a.billingschedule,a.modalfactor,a.annualamount,a.amount,a.amountprorate,a.effectivity,a.modalfrom,a.modalto,a.monthused,a.monthcovered,a.soacode,a.soano
			,a.dummymemberno,a.dateencoded,a.encodedby,a.premiumclass
		FROM tblmemberfees a WITH(NOLOCK)
		LEFT JOIN tblmemberuploaddetails b WITH(NOLOCK) ON b.compcode = a.compcode AND a.batchcode = b.batchcode AND a.membercode = b.membercode and b.waived = 0
		WHERE a.compcode = @lcompcode  AND a.contractcode = @lcontractcode AND a.batchcode = @lbatchcode AND a.active = 1
		OPTION(RECOMPILE)

		SET @SQL = N'UPDATE a SET a.memberno = ISNULL(b.memberno, ''''), a.membername = ISNULL(b.membername, ''''), a.classorder = ISNULL(b.classorder, 0)
		FROM '+QUOTENAME(@DBname)+'.dbo.tblsoaaccountsummarydetail a
		LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b ON b.compcode = a.compcode AND a.membercode = b.membercode
		WHERE a.compcode = @lcompcode AND a.batchcode = @lbatchcode
		OPTION(RECOMPILE)'

		EXEC master.sys.sp_executesql
		@SQL,
		N'@lcompcode INT, @lbatchcode INT',
		@lcompcode = @lcompcode,
		@lbatchcode = @lbatchcode
	
	END

	IF @lfromwebagent = 0
	BEGIN
		SET @lportalcode =  (SELECT portalcode FROM tblmemberuploadbatch WHERE compcode = @lcompcode AND batchcode = @lbatchcode)
		
		--SET @SQL = 'INSERT INTO tblsoaaccountsummarydetail(summarycode,memberfeecode,compcode,contractcode,billclassdetno,premiumcode,feecode,membercode,batchcode
		--	,active,cancelled,billingschedule,modalfactor,annualamount,amount,amountprorate,effectivity,modalfrom,modalto,monthused,monthcovered,soacode,soano
		--	,dummymemberno,dateencoded,encodedby,premiumclass)
		--SELECT '+CONVERT(VARCHAR(20), @lsummarycode)+',a.memberfeecode,a.compcode,a.contractcode,a.billclassdetno,a.premiumcode,a.feecode,a.membercode,a.batchcode,a.active,a.cancelled
		--	,a.billingschedule,a.modalfactor,a.annualamount,
		--	a.amount - ISNULL(c.amount, 0),
		--	a.amountprorate - ISNULL(c.amountprorate, 0),
		--	a.effectivity,a.modalfrom,a.modalto,a.monthused,a.monthcovered,a.soacode,a.soano
		--	,a.dummymemberno,a.dateencoded,a.encodedby,a.premiumclass
		--FROM '+@DBname+'.dbo.tblmemberfees a WITH(NOLOCK)
		--OUTER APPLY(SELECT compcode, membercode, membercategory, effectivity, modalfrom, modalto,waived FROM tblmemberuploaddetails b WITH(NOLOCK) WHERE b.compcode = a.compcode AND a.batchcode = b.batchcode AND a.membercode = b.membercode and b.waived = 0) b
		--OUTER APPLY(SELECT amount, amountprorate FROM '+@DBname+'.dbo.tblmemberfees c WITH(NOLOCK) WHERE a.compcode = c.compcode AND a.contractcode = c.contractcode AND a.batchcode <> c.batchcode AND a.feecode = c.feecode AND a.membercode = c.membercode AND c.active = 1 AND c.cancelled = 0) c
		--OUTER APPLY(SELECT batchtype FROM tblmemberuploadbatch d WITH(NOLOCK) WHERE a.batchcode = d.batchcode) d
		--WHERE a.compcode = '+CONVERT(VARCHAR(20), @lcompcode)+'  AND a.contractcode = '+CONVERT(VARCHAR(20), @lcontractcode)+' AND a.batchcode = '+CONVERT(VARCHAR(20), @lbatchcode)+' AND a.active = 1
		--OPTION(RECOMPILE)'

		--EXEC (@SQL)

		INSERT INTO tblsoaaccountsummarydetail(summarycode,memberfeecode,compcode,contractcode,billclassdetno,premiumcode,feecode,membercode,batchcode
			,active,cancelled,billingschedule,modalfactor,annualamount,amount,amountprorate,effectivity,modalfrom,modalto,monthused,monthcovered,soacode,soano
			,dummymemberno,dateencoded,encodedby,premiumclass)
		SELECT @lsummarycode,a.memberfeecode,a.compcode,a.contractcode,a.billclassdetno,a.premiumcode,a.feecode,a.membercode,a.batchcode,a.active,a.cancelled
			,a.billingschedule,a.modalfactor,a.annualamount,a.amount,a.amountprorate,a.effectivity,a.modalfrom,a.modalto,a.monthused,a.monthcovered,a.soacode,a.soano
			,a.dummymemberno,a.dateencoded,a.encodedby,a.premiumclass
		FROM tblmemberfees a WITH(NOLOCK)
		LEFT JOIN tblmemberuploaddetails b WITH(NOLOCK) ON b.compcode = a.compcode AND a.batchcode = b.batchcode AND a.membercode = b.membercode and b.waived = 0
		WHERE a.compcode = @lcompcode  AND a.contractcode = @lcontractcode AND a.batchcode = @lbatchcode AND a.active = 1
		OPTION(RECOMPILE)

		SET @SQL = N'UPDATE a SET a.memberno = ISNULL(b.memberno, ''''), a.membername = ISNULL(b.membername, ''''), a.classorder = ISNULL(b.classorder, 0)
		FROM '+QUOTENAME(@DBname)+'.dbo.tblsoaaccountsummarydetail a WITH(NOLOCK)
		LEFT JOIN '+QUOTENAME(@DBname)+'.dbo.tblmembers b ON b.compcode = a.compcode AND a.membercode = b.membercode
		WHERE a.compcode = @lcompcode AND a.batchcode = @lbatchcode
		OPTION(RECOMPILE)'

		EXEC master.sys.sp_executesql
		@SQL,
		N'@lcompcode INT, @lbatchcode INT',
		@lcompcode = @lcompcode,
		@lbatchcode = @lbatchcode
	
	END
END
GO

-- ---- sp_uploadmemsavesoaaccountsummaryv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemsavesoaaccountsummaryv2] --6983, 9402, 68825, 0, 0, 1
	-- Add the parameters for the stored procedure here
	
	@compcode		Int,
	@contractcode	Int,
	@batchcode		Int,
	@approvedby		Int,
	@fromwebagent	Tinyint = 0
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    DECLARE @lcompcode		Int				= @compcode,
			@lcontractcode	Int				= @contractcode,
			@lbatchcode		Int				= @batchcode,
			@lapprovedby	Int				= @approvedby,
			@lsummarycode	Int				= 0,
			@lbatchtype		VARCHAR(20)		= ''

	SELECT
	@lbatchtype = RTRIM(UPPER(batchtype))
	FROM tblmemberuploadbatch 
	WHERE batchcode = @lbatchcode
	
	SET @lsummarycode = ISNULL((SELECT summarycode FROM tblsoaaccountsummary WHERE compcode = @lcompcode AND batchcode = @lbatchcode), 0)


	--- INSERT SUMMARY ---

	IF @lsummarycode = 0
		BEGIN	
			INSERT INTO tblsoaaccountsummary(compcode, contractcode, batchcode, batchno,
			totalcount, batchtype, uploadsetup, uploadedby, dateuploaded, approvedby, dateapproved)
			SELECT compcode, contractcode, batchcode, batchno,
			uploaded, batchtype, uploadsetup, uploadedby, dateuploaded, @lapprovedby, GETDATE()
			FROM tblmemberuploadbatch
			WHERE compcode = @lcompcode AND contractcode = @lcontractcode AND batchcode = @lbatchcode
			OPTION(RECOMPILE)
		END

	--- UPDATE SUMMARY --- (@lsummarycode <> 0)
	ELSE
		BEGIN
			UPDATE tblsoaaccountsummary SET approvedby = @lapprovedby, dateapproved = GETDATE() WHERE summarycode = @lsummarycode
		END

END
GO

-- ---- sp_uploadmemupdateamendmentmemberdetailsv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemupdateamendmentmemberdetailsv2]
	@portalcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	INT = @portalcode,
			@lcompcode		INT = 0



	SELECT @lcompcode = compcode
	FROM tblportalupload
	WHERE portalcode = @lportalcode


    UPDATE b SET
	occupation = CASE WHEN  UPPER(a.occupation) = 'NULL' THEN '' 
		WHEN a.occupation <> '' THEN a.occupation 
		ELSE b.occupation END
	,civilstatus = CASE 
		WHEN a.civilstatus <> 0 THEN a.civilstatus 
		ELSE b.civilstatus END
	,officephone = CASE WHEN UPPER(a.officephone) ='NULL' THEN '' 
		WHEN a.officephone <> '' THEN a.officephone 
		ELSE b.officephone END
	,mobile = CASE WHEN RTRIM(LTRIM(UPPER(rawmobile))) = 'NULL' THEN '' 
		WHEN RTRIM(LTRIM(UPPER(rawmobile))) <> '' THEN a.mobile
		ELSE b.mobile END
	,emailaddress = CASE WHEN RTRIM(LTRIM(UPPER(rawemailaddress))) = 'NULL' THEN '' 
		WHEN RTRIM(LTRIM(UPPER(rawemailaddress))) <> '' THEN a.emailaddress 
		ELSE b.emailaddress END
	,telephone = CASE WHEN UPPER(a.homephone) ='NULL' THEN '' 
		WHEN a.homephone <> '' THEN a.homephone 
		ELSE b.telephone END
	,sssno = CASE WHEN UPPER(a.sssno) = 'NULL' THEN '' 
		WHEN a.sssno <> '' THEN a.sssno 
		ELSE b.sssno END
	,tin = CASE WHEN UPPER(a.tin) = 'NULL' THEN '' 
		WHEN a.tin <> '' THEN a.tin 
		ELSE  b.tin END
	,officefax = CASE 
		WHEN a.officefax <> '' THEN a.officefax 
		ELSE b.officefax END
	,dependentcoveragetype = CASE 
		WHEN a.dependentcoveragetype <> '' THEN a.dependentcoveragetype 
		ELSE b.dependentcoveragetype END
	FROM tblportaluploaddetails a WITH(NOLOCK)
	LEFT JOIN tblmemberdetails b ON b.compcode = @lcompcode and a.membercode = b.membercode
	WHERE a.portalcode = @lportalcode and b.membercode <> 0 and a.uploadtype = 'A-MP'
	OPTION(RECOMPILE)
END
GO

-- ---- sp_uploadmemupdateamendmentmembersv2 ----
CREATE   PROCEDURE [dbo].[sp_uploadmemupdateamendmentmembersv2]
	@portalcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	INT = @portalcode,
			@lcompcode		INT = 0,
			@lnullencrypt varchar(240) = ''

	EXEC sp_opensymmetric

			set @lnullencrypt = dbo.Encrypt(RTRIM(LTRIM(UPPER('NULL'))))
			
	EXEC sp_closesymmetric

	SELECT @lcompcode = compcode
	FROM tblportalupload
	WHERE portalcode = @lportalcode

    UPDATE b SET 
	streetaddress = 
		CASE WHEN UPPER(a.streetaddress) = 'NULL' THEN '' 
		WHEN a.streetaddress <> '' THEN a.streetaddress 
		ELSE ISNULL(b.streetaddress, a.streetaddress) END ,

	relation = 
		CASE WHEN UPPER(a.relationship) = @lnullencrypt THEN '' 
		WHEN a.relationship <> '' THEN a.relationship 
		ELSE ISNULL(b.relation, a.relationship) END ,

	civilstatus = 
		CASE WHEN a.civilstatus <> 0 THEN a.civilstatus 
		ELSE ISNULL(b.civilstatus, a.civilstatus) END ,

	policydivision = 
		CASE WHEN a.policydivision <> 0 THEN a.policydivision 
		ELSE ISNULL(b.policydivision, a.policydivision) END

	FROM tblportaluploaddetails a WITH(NOLOCK)
	LEFT JOIN tblmembers b 
		ON b.compcode = @lcompcode and a.membercode = b.membercode

	WHERE a.portalcode = @lportalcode and b.membercode <> 0 and a.uploadtype = 'A-MP'
	OPTION(RECOMPILE)
END
GO

-- ---- sp_uploadmemupdateamendmentmembersv3 ----
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
CREATE   PROCEDURE [dbo].[sp_uploadmemupdateamendmentmembersv3]
	@portalcode		INT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @lportalcode	INT = @portalcode,
			@lcompcode		INT = 0,
			@lnullencrypt varchar(240) = ''

	EXEC sp_opensymmetric

			set @lnullencrypt = dbo.Encrypt(RTRIM(LTRIM(UPPER('NULL'))))
			
	EXEC sp_closesymmetric

	SELECT @lcompcode = compcode
	FROM tblportalupload
	WHERE portalcode = @lportalcode

    UPDATE b SET 
	streetaddress = 
		CASE WHEN UPPER(a.streetaddress) = 'NULL' THEN '' 
		WHEN a.streetaddress <> '' THEN a.streetaddress 
		ELSE ISNULL(b.streetaddress, a.streetaddress) END ,

	relation = 
		CASE WHEN UPPER(a.relationship) = @lnullencrypt THEN '' 
		WHEN a.relationship <> '' THEN a.relationship 
		ELSE ISNULL(b.relation, a.relationship) END ,

	civilstatus = 
		CASE WHEN a.civilstatus <> 0 THEN a.civilstatus 
		ELSE ISNULL(b.civilstatus, a.civilstatus) END ,

	policydivision = 
		CASE WHEN a.policydivision <> 0 THEN a.policydivision 
		ELSE ISNULL(b.policydivision, a.policydivision) END,

	employeeno = 
		CASE WHEN a.employeeno <> '' THEN a.employeeno 
		ELSE ISNULL(b.employeeno, a.employeeno) END
	FROM tblportaluploaddetails a WITH(NOLOCK)

	LEFT JOIN tblmembers b 
		ON b.compcode = @lcompcode and a.membercode = b.membercode

	WHERE a.portalcode = @lportalcode and b.membercode <> 0 and a.uploadtype = 'A-MP'
	OPTION(RECOMPILE)
END
GO

-- ---- sp_uploadmemupdatebillingschedulev2 ----
CREATE PROCEDURE [dbo].[sp_uploadmemupdatebillingschedulev2]
	-- Add the parameters for the stored procedure here
	
	@batchcode Int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	DECLARE @lbatchcode			Int				= @batchcode;

	DECLARE @SQL			NVARCHAR(MAX)	= '',
			@DBname			Varchar(150)	= (SELECT dbmasmembers FROM tblsettingsunderwriting WITH(NOLOCK))

    -- Insert statements for procedure here.
	SET @SQL = 
	N'UPDATE a SET
	billingschedule = ISNULL(b.billingschedule, a.billingschedule)
	FROM '+QUOTENAME(@DBname)+'.dbo.tblmembers a WITH(NOLOCK)
	INNER JOIN 
	(
		SELECT DISTINCT membercode, billingschedule
		FROM '+QUOTENAME(@DBname)+'.dbo.tblmemberfees WITH(NOLOCK)
		WHERE batchcode = @lbatchcode
	)b ON a.membercode = b.membercode
	WHERE a.billingschedule <> b.billingschedule
	OPTION(RECOMPILE)
	'
	EXEC master.sys.sp_executesql
	@SQL,
	N'@lbatchcode INT',
	@lbatchcode = @lbatchcode


END
GO

