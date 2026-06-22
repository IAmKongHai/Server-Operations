-- ============================================================
-- 目的: 把完整库 medicalassistance 有、但 _preprod 缺的
--       表和字段补进 medicalassistance_preprod
-- 来源: medicalassistance_20260620_sql.sql (完整库结构)
-- 排除: tblcompany_maskingbackup / tblmembers_maskingbackup (脱敏临时表)
-- 缺失列: NOT NULL 列已加 DEFAULT，避免对已有数据 ADD 失败
-- 注意: 执行前请在 preprod 上备份; 建议先在测试环境验证
-- ============================================================
USE [medicalassistance_preprod];
GO

-- ========== 第一部分: 新建缺失的 11 张表 ==========

-- ---- dbo.tblbatchloamapping ----
IF OBJECT_ID(N'[dbo].[tblbatchloamapping]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblbatchloamapping](
	[batchcode] [int] IDENTITY(1,1) NOT NULL,
	[batchno] [varchar](20) NOT NULL,
	[statuscode] [tinyint] NULL,
	[dateuploaded] [datetime] NOT NULL,
	[datestarted] [datetime] NOT NULL,
	[datefinished] [datetime] NOT NULL,
	[duration] [varchar](50) NOT NULL,
	[filename] [varchar](250) NOT NULL,
	[remarks] [varchar](250) NOT NULL,
	[uploadcount] [int] NOT NULL,
	[uploadedby] [int] NOT NULL,
	[uploadtype] [int] NOT NULL,
	[requiredfields] [varchar](700) NOT NULL,
	[loamappingfilename] [varchar](100) NOT NULL,
 CONSTRAINT [PK_tblbatchloamapping] PRIMARY KEY CLUSTERED 
(
	[batchcode] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tblbatchloamappingdetails ----
IF OBJECT_ID(N'[dbo].[tblbatchloamappingdetails]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblbatchloamappingdetails](
	[detno] [int] IDENTITY(1,1) NOT NULL,
	[memberno] [varchar](30) NOT NULL,
	[approvalcode] [varchar](20) NOT NULL,
	[dateavailed] [smalldatetime] NOT NULL,
	[cptcode] [varchar](30) NOT NULL,
	[sacode] [varchar](30) NOT NULL,
	[icdcode] [varchar](30) NOT NULL,
	[billno] [varchar](30) NOT NULL,
	[remarks] [varchar](240) NOT NULL,
	[failedremarks] [varchar](240) NOT NULL,
	[batchcode] [int] NOT NULL,
	[subclaimtypedesc] [varchar](30) NOT NULL,
	[amount] [numeric](18, 2) NOT NULL,
 CONSTRAINT [PK_tblbatchloamappingdetails] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tblbatchloamappingdummydetails ----
IF OBJECT_ID(N'[dbo].[tblbatchloamappingdummydetails]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblbatchloamappingdummydetails](
	[detno] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[batchcode] [int] NOT NULL,
	[memberno] [varchar](30) NOT NULL,
	[amount] [numeric](18, 2) NOT NULL,
	[subclaimtypedesc] [varchar](20) NOT NULL,
	[approvalcode] [varchar](30) NOT NULL,
	[dateavailed] [smalldatetime] NOT NULL,
	[cptcode] [varchar](30) NOT NULL,
	[sacode] [varchar](30) NOT NULL,
	[icdcode] [varchar](30) NOT NULL,
	[billno] [varchar](30) NOT NULL,
	[rowno] [int] NOT NULL,
 CONSTRAINT [PK_tblbatchloamappingdummydetails] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tblclaimreimrequirements ----
IF OBJECT_ID(N'[dbo].[tblclaimreimrequirements]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblclaimreimrequirements](
	[detno] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[billcode] [int] NOT NULL,
	[requirementcode] [int] NOT NULL,
	[remarks] [varchar](100) NOT NULL,
	[postedby] [smallint] NOT NULL,
	[dateposted] [smalldatetime] NOT NULL,
 CONSTRAINT [PK_tblclaimreimrequirements] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tblcompanyclassesvpdlink ----
IF OBJECT_ID(N'[dbo].[tblcompanyclassesvpdlink]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblcompanyclassesvpdlink](
	[detno] [int] IDENTITY(1,1) NOT NULL,
	[classdetno] [int] NOT NULL,
	[encodedby] [int] NOT NULL,
	[dateencoded] [smalldatetime] NOT NULL,
	[parentclassdetno] [int] NOT NULL,
 CONSTRAINT [PK_tblcompanyclassesvpdlink] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tbldoctorewtdetails ----
IF OBJECT_ID(N'[dbo].[tbldoctorewtdetails]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tbldoctorewtdetails](
	[detno] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[doctorcode] [int] NOT NULL,
	[wtaxno] [int] NOT NULL,
	[effectivity] [smalldatetime] NOT NULL,
	[expiry] [smalldatetime] NOT NULL,
	[encodedby] [int] NOT NULL,
	[dateencoded] [smalldatetime] NOT NULL,
	[batchcode] [int] NOT NULL,
 CONSTRAINT [PK_tbldoctorewtdetails] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tbldoctorewtjournal ----
IF OBJECT_ID(N'[dbo].[tbldoctorewtjournal]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tbldoctorewtjournal](
	[detno] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[ewtdetaildetno] [int] NOT NULL,
	[datecreated] [smalldatetime] NOT NULL,
	[description] [varchar](200) NOT NULL,
	[userno] [smallint] NOT NULL,
 CONSTRAINT [PK_tbldoctorewtjournal] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tblfranchiseuserauditlevel ----
IF OBJECT_ID(N'[dbo].[tblfranchiseuserauditlevel]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblfranchiseuserauditlevel](
	[detno] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[recordcode] [int] NOT NULL,
	[userno] [int] NOT NULL,
	[dateencoded] [smalldatetime] NOT NULL,
	[encodedby] [smallint] NOT NULL,
 CONSTRAINT [PK_tblfranchiseuserauditlevel] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tblmemberportalsettingsjournal ----
IF OBJECT_ID(N'[dbo].[tblmemberportalsettingsjournal]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblmemberportalsettingsjournal](
	[detno] [int] IDENTITY(1,1) NOT NULL,
	[memberportalsettingsno] [int] NOT NULL,
	[description] [varchar](240) NOT NULL,
	[required] [bit] NOT NULL,
	[dateencoded] [smalldatetime] NOT NULL,
	[encodedby] [int] NOT NULL,
 CONSTRAINT [PK_tblmemberportalsettingsjournal] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tblmembertermination ----
IF OBJECT_ID(N'[dbo].[tblmembertermination]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblmembertermination](
	[terminationno] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[compcode] [int] NOT NULL,
	[membercode] [int] NOT NULL,
	[effectivity] [smalldatetime] NOT NULL,
	[processed] [bit] NOT NULL,
	[dateprocessed] [smalldatetime] NOT NULL,
	[dateencoded] [smalldatetime] NOT NULL,
 CONSTRAINT [PK_tblmembertermination] PRIMARY KEY CLUSTERED 
(
	[terminationno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO

-- ---- dbo.tblunconfirmedmembers ----
IF OBJECT_ID(N'[dbo].[tblunconfirmedmembers]', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tblunconfirmedmembers](
	[detno] [int] IDENTITY(1,1) NOT NULL,
	[compcode] [int] NOT NULL,
	[membercode] [int] NOT NULL,
	[subscriptionuserno] [int] NOT NULL,
	[batchno] [varchar](50) NOT NULL,
	[unconfirmeddate] [smalldatetime] NOT NULL,
	[encodedby] [int] NOT NULL,
	[dateencoded] [smalldatetime] NOT NULL,
 CONSTRAINT [PK_tblunconfirmedmembers] PRIMARY KEY CLUSTERED 
(
	[detno] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO


-- ========== 第二部分: 给共有表补缺失字段 ==========


-- ---- dbo.tblagents ----
ALTER TABLE [dbo].[tblagents] ADD [franchisecode] INT NOT NULL CONSTRAINT [DF_tblagents_franchisecode] DEFAULT (0);

-- ---- dbo.tblapplicationjournals ----
ALTER TABLE [dbo].[tblapplicationjournals] ADD [franchisecode] INT NOT NULL CONSTRAINT [DF_tblapplicationjournals_franchisecode] DEFAULT (0);

-- ---- dbo.tblapplicationmedhistory ----
ALTER TABLE [dbo].[tblapplicationmedhistory] ADD [franchisecode] INT NOT NULL CONSTRAINT [DF_tblapplicationmedhistory_franchisecode] DEFAULT (0);

-- ---- dbo.tblapplicationprevillnesses ----
ALTER TABLE [dbo].[tblapplicationprevillnesses] ADD [franchisecode] INT NOT NULL CONSTRAINT [DF_tblapplicationprevillnesses_franchisecode] DEFAULT (0);

-- ---- dbo.tblapplications ----
ALTER TABLE [dbo].[tblapplications] ADD [payorrelationship1] TINYINT NOT NULL CONSTRAINT [DF_tblapplications_payorrelationship1] DEFAULT (0);
ALTER TABLE [dbo].[tblapplications] ADD [payorrelationship2] VARCHAR(100) NOT NULL CONSTRAINT [DF_tblapplications_payorrelationship2] DEFAULT ('');

-- ---- dbo.tblauthoritytodeductsettings ----
ALTER TABLE [dbo].[tblauthoritytodeductsettings] ADD [atdtext] VARCHAR(500) NOT NULL CONSTRAINT [DF_tblauthoritytodeductsettings_atdtext] DEFAULT ('');

-- ---- dbo.tblbenefitsa ----
ALTER TABLE [dbo].[tblbenefitsa] ADD [dentalcoverage] TINYINT NOT NULL CONSTRAINT [DF_tblbenefitsa_dentalcoverage] DEFAULT (0);
ALTER TABLE [dbo].[tblbenefitsa] ADD [iorta] BIT NOT NULL CONSTRAINT [DF_tblbenefitsa_iorta] DEFAULT (0);

-- ---- dbo.tblcompanybenefitplan ----
ALTER TABLE [dbo].[tblcompanybenefitplan] ADD [limitsetupothers] VARCHAR(200) NOT NULL CONSTRAINT [DF_tblcompanybenefitplan_limitsetupothers] DEFAULT ('');

-- ---- dbo.tblcompanyclasses ----
ALTER TABLE [dbo].[tblcompanyclasses] ADD [cancellationdays] INT NOT NULL CONSTRAINT [DF_tblcompanyclasses_cancellationdays] DEFAULT (0);
ALTER TABLE [dbo].[tblcompanyclasses] ADD [clinicbased] BIT NOT NULL CONSTRAINT [DF_tblcompanyclasses_clinicbased] DEFAULT (0);
ALTER TABLE [dbo].[tblcompanyclasses] ADD [dentalinformation] BIT NOT NULL CONSTRAINT [DF_tblcompanyclasses_dentalinformation] DEFAULT (0);
ALTER TABLE [dbo].[tblcompanyclasses] ADD [vpdlinkcode] INT NOT NULL CONSTRAINT [DF_tblcompanyclasses_vpdlinkcode] DEFAULT (0);

-- ---- dbo.tblcompanyclassesbilling ----
ALTER TABLE [dbo].[tblcompanyclassesbilling] ADD [roomcategory] INT NOT NULL CONSTRAINT [DF_tblcompanyclassesbilling_roomcategory] DEFAULT (0);

-- ---- dbo.tblcompanycontractyears ----
ALTER TABLE [dbo].[tblcompanycontractyears] ADD [autorenewal] VARCHAR(50) NOT NULL CONSTRAINT [DF_tblcompanycontractyears_autorenewal] DEFAULT ('');
ALTER TABLE [dbo].[tblcompanycontractyears] ADD [renewalcontractcode] INT NOT NULL CONSTRAINT [DF_tblcompanycontractyears_renewalcontractcode] DEFAULT (0);

-- ---- dbo.tblexceptions ----
ALTER TABLE [dbo].[tblexceptions] ADD [remarks] VARCHAR(240) NOT NULL CONSTRAINT [DF_tblexceptions_remarks] DEFAULT ('');
ALTER TABLE [dbo].[tblexceptions] ADD [sra] VARCHAR(100) NOT NULL CONSTRAINT [DF_tblexceptions_sra] DEFAULT ('');

-- ---- dbo.tblmemberportalsettings ----
ALTER TABLE [dbo].[tblmemberportalsettings] ADD [dependenttopup] BIT NOT NULL CONSTRAINT [DF_tblmemberportalsettings_dependenttopup] DEFAULT (0);
ALTER TABLE [dbo].[tblmemberportalsettings] ADD [showconfirm] BIT NOT NULL CONSTRAINT [DF_tblmemberportalsettings_showconfirm] DEFAULT (0);

-- ---- dbo.tblmembers ----
ALTER TABLE [dbo].[tblmembers] ADD [cdmpapprovedby] INT NOT NULL CONSTRAINT [DF_tblmembers_cdmpapprovedby] DEFAULT (0);
ALTER TABLE [dbo].[tblmembers] ADD [cdmpapproveddate] SMALLDATETIME NOT NULL CONSTRAINT [DF_tblmembers_cdmpapproveddate] DEFAULT ('1900-01-01');

-- ---- dbo.tblmemberuploadbatch ----
ALTER TABLE [dbo].[tblmemberuploadbatch] ADD [autorenewal] VARCHAR(50) NOT NULL CONSTRAINT [DF_tblmemberuploadbatch_autorenewal] DEFAULT ('');

-- ---- dbo.tblportalupload ----
ALTER TABLE [dbo].[tblportalupload] ADD [autorenewal] VARCHAR(50) NOT NULL CONSTRAINT [DF_tblportalupload_autorenewal] DEFAULT ('');

-- ---- dbo.tblproductlines ----
ALTER TABLE [dbo].[tblproductlines] ADD [iorta] BIT NOT NULL CONSTRAINT [DF_tblproductlines_iorta] DEFAULT (0);

-- ---- dbo.tblsettingsmedical ----
ALTER TABLE [dbo].[tblsettingsmedical] ADD [loamappingarchive] VARCHAR(250) NOT NULL CONSTRAINT [DF_tblsettingsmedical_loamappingarchive] DEFAULT ('');
ALTER TABLE [dbo].[tblsettingsmedical] ADD [loamappingdefaulticd] VARCHAR(20) NOT NULL CONSTRAINT [DF_tblsettingsmedical_loamappingdefaulticd] DEFAULT ('');
ALTER TABLE [dbo].[tblsettingsmedical] ADD [loamappinginbox] VARCHAR(250) NOT NULL CONSTRAINT [DF_tblsettingsmedical_loamappinginbox] DEFAULT ('');

-- ---- dbo.tblsettingsunderwriting ----
ALTER TABLE [dbo].[tblsettingsunderwriting] ADD [dcftemplatepath] VARCHAR(150) NOT NULL CONSTRAINT [DF_tblsettingsunderwriting_dcftemplatepath] DEFAULT ('');
ALTER TABLE [dbo].[tblsettingsunderwriting] ADD [settingcode] INT NOT NULL CONSTRAINT [DF_tblsettingsunderwriting_settingcode] DEFAULT (0);

-- ---- dbo.tblsettingsweb ----
ALTER TABLE [dbo].[tblsettingsweb] ADD [cdmpcurrentmedicationpath] VARCHAR(200) NOT NULL CONSTRAINT [DF_tblsettingsweb_cdmpcurrentmedicationpath] DEFAULT ('');
ALTER TABLE [dbo].[tblsettingsweb] ADD [cdmphealthcoachappointmentspath] VARCHAR(200) NOT NULL CONSTRAINT [DF_tblsettingsweb_cdmphealthcoachappointmentspath] DEFAULT ('');
ALTER TABLE [dbo].[tblsettingsweb] ADD [cdmphomelaboratoryexampath] VARCHAR(200) NOT NULL CONSTRAINT [DF_tblsettingsweb_cdmphomelaboratoryexampath] DEFAULT ('');
ALTER TABLE [dbo].[tblsettingsweb] ADD [cdmpmedicaldeclarationpath] VARCHAR(200) NOT NULL CONSTRAINT [DF_tblsettingsweb_cdmpmedicaldeclarationpath] DEFAULT ('');
ALTER TABLE [dbo].[tblsettingsweb] ADD [cdmpnutritioncounsellingpath] VARCHAR(200) NOT NULL CONSTRAINT [DF_tblsettingsweb_cdmpnutritioncounsellingpath] DEFAULT ('');
ALTER TABLE [dbo].[tblsettingsweb] ADD [cdmpresourcecenterpath] VARCHAR(200) NOT NULL CONSTRAINT [DF_tblsettingsweb_cdmpresourcecenterpath] DEFAULT ('');

-- ---- dbo.tbluploadbatchclaims ----
ALTER TABLE [dbo].[tbluploadbatchclaims] ADD [adjudication] TINYINT NOT NULL CONSTRAINT [DF_tbluploadbatchclaims_adjudication] DEFAULT (0);
ALTER TABLE [dbo].[tbluploadbatchclaims] ADD [cancelledby] INT NOT NULL CONSTRAINT [DF_tbluploadbatchclaims_cancelledby] DEFAULT (0);
ALTER TABLE [dbo].[tbluploadbatchclaims] ADD [datecancelled] SMALLDATETIME NOT NULL CONSTRAINT [DF_tbluploadbatchclaims_datecancelled] DEFAULT ('1900-01-01');
GO
