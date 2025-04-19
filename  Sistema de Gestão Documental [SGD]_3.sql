use SGD;

CREATE TABLE TipoDocumento (
    TipoID INT PRIMARY KEY,
    Descricao VARCHAR(255) NOT NULL 
);

CREATE TABLE Estado (
    EstadoID INT PRIMARY KEY,
    Nome VARCHAR(255) NOT NULL UNIQUE  
);

CREATE TABLE UnidadeOrganica (
    UnidadeOrganicaID INT PRIMARY KEY,
    Nome VARCHAR(255) NOT NULL UNIQUE  
);

CREATE TABLE ArquivoDocumental (
    ArquivoID INT PRIMARY KEY,
    Localizacao VARCHAR(255) NOT NULL,
    Referencia VARCHAR(255) NOT NULL
);

CREATE TABLE Documentos (
    DocumentoID INT PRIMARY KEY,
    TipoID INT NOT NULL,
    EstadoID INT NOT NULL,  -- Corrigido de "Estado" para "EstadoID"
    DataRecepcao DATE NOT NULL,
    DataCriacao DATE DEFAULT '2000-01-01',
    DataHoraInsercao DATETIME DEFAULT GETDATE(), 
    UnidadeOrganicaID INT NOT NULL,
    ReferenciaArquivo INT,
    Descricao VARCHAR(255) NOT NULL,
    FOREIGN KEY (TipoID) REFERENCES TipoDocumento(TipoID),
    FOREIGN KEY (EstadoID) REFERENCES Estado(EstadoID),  -- Correção na referência
    FOREIGN KEY (UnidadeOrganicaID) REFERENCES UnidadeOrganica(UnidadeOrganicaID),
    FOREIGN KEY (ReferenciaArquivo) REFERENCES ArquivoDocumental(ArquivoID)
);

ALTER TABLE Documentos
ADD Hiden BIT DEFAULT 0;



CREATE TABLE Secretariado (
    SecretariadoID INT PRIMARY KEY,
    Nome VARCHAR(255) NOT NULL
);

CREATE TABLE RegrasEncaminhamento (
    RegraID INT PRIMARY KEY,
    Nome VARCHAR(255) NOT NULL,
    Prazo INT NOT NULL
);

CREATE TABLE CriteriosEncaminhamento (
    CriterioID INT PRIMARY KEY,
    RegraID INT NOT NULL,
    Descricao VARCHAR(255) NOT NULL,
    FOREIGN KEY (RegraID) REFERENCES RegrasEncaminhamento(RegraID)
);

CREATE TABLE TipoNotificacao (
    TipoID INT PRIMARY KEY,
    Descricao VARCHAR(255) NOT NULL
);

CREATE TABLE Intervenientes (
    IntervenienteID INT PRIMARY KEY,
    Nome VARCHAR(255) NOT NULL,
    Tipo VARCHAR(50) NOT NULL,
    UnidadeOrganicaID INT,
    FOREIGN KEY (UnidadeOrganicaID) REFERENCES UnidadeOrganica(UnidadeOrganicaID)
);

CREATE TABLE Notificacoes (
    NotificacaoID INT PRIMARY KEY,
    TipoID INT NOT NULL,
    Conteudo TEXT NOT NULL,
    DestinatarioID INT NOT NULL,
    FOREIGN KEY (TipoID) REFERENCES TipoNotificacao(TipoID),
    FOREIGN KEY (DestinatarioID) REFERENCES Intervenientes(IntervenienteID)
);

CREATE TABLE LogAtividades (
    LogID INT PRIMARY KEY,
    DocumentoID INT NOT NULL,
    Acao VARCHAR(255) NOT NULL,
    DataHora DATETIME NOT NULL,
    IntervenienteID INT NOT NULL,
    FOREIGN KEY (DocumentoID) REFERENCES Documentos(DocumentoID),
    FOREIGN KEY (IntervenienteID) REFERENCES Intervenientes(IntervenienteID)
);

ALTER TABLE LogAtividades
ADD BlockchainKey VARBINARY(256);


CREATE TABLE Certidoes (
    NumeroDocumento INT PRIMARY KEY,
    NomeCertidao VARCHAR(255) NOT NULL,
    DataExpiracao DATE NOT NULL
);

CREATE TABLE Faturas (
    NumeroDocumento INT PRIMARY KEY,
    NIPC_Vendedor VARCHAR(20) NOT NULL,
    NIF_Comprador VARCHAR(20) NOT NULL,
    DataFatura DATE NOT NULL,
    ValorTotal DECIMAL(10, 2) NOT NULL
);

ALTER TABLE Documentos
ADD Confidencial BIT DEFAULT 0;

GO
--Funções/Procedimentos
CREATE FUNCTION dbo.HistoricoDocumento (@DocumentoID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        l.LogID, 
        l.Acao, 
        l.DataHora, 
        i.Nome AS Interveniente, 
        d.DocumentoID, 
        d.Descricao, 
        e.Nome AS Estado, 
        u.Nome AS UnidadeOrganica
    FROM 
        LogAtividades l
    JOIN 
        Intervenientes i ON l.IntervenienteID = i.IntervenienteID
    JOIN 
        Documentos d ON l.DocumentoID = d.DocumentoID
    JOIN 
        Estado e ON d.EstadoID = e.EstadoID
    JOIN 
        UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
    WHERE 
        l.DocumentoID = @DocumentoID
);


GO
CREATE FUNCTION dbo.UltimoEstadoDocumento (@DocumentoID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP 1 
        e.Nome AS Estado, 
        l.DataHora AS UltimaAlteracao
    FROM 
        LogAtividades l
    JOIN 
        Estado e ON l.DocumentoID = @DocumentoID AND e.EstadoID = (
            SELECT d.EstadoID
            FROM Documentos d
            WHERE d.DocumentoID = l.DocumentoID
        )
    WHERE 
        l.DocumentoID = @DocumentoID
    ORDER BY l.LogID DESC
);

GO
CREATE FUNCTION dbo.ContagemDocumentosPorEstado ()
RETURNS TABLE
AS
RETURN
(
    SELECT 
        e.Nome AS Estado,
        COUNT(d.DocumentoID) AS TotalDocumentos
    FROM 
        Documentos d
    JOIN 
        Estado e ON d.EstadoID = e.EstadoID
    GROUP BY 
        e.Nome
);

GO
CREATE PROCEDURE dbo.ListarDocumentosConfidenciais
AS
BEGIN
    SELECT 
        d.DocumentoID, 
        d.Descricao, 
        d.DataRecepcao, 
        u.Nome AS UnidadeOrganica, 
        e.Nome AS Estado, 
        d.Confidencial
    FROM 
        Documentos d
    JOIN 
        UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
    JOIN 
        Estado e ON d.EstadoID = e.EstadoID
    WHERE 
        d.Confidencial = 1;
END;

GO
CREATE PROCEDURE dbo.ListarDocumentosJuridico
AS
BEGIN
    SELECT 
        d.DocumentoID, 
        d.Descricao, 
        d.DataRecepcao, 
        u.Nome AS UnidadeOrganica, 
        estado.Estado AS EstadoAtual, 
        estado.UltimaAlteracao AS DataUltimaAlteracao
    FROM 
        Documentos d
    JOIN 
        UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
    CROSS APPLY 
        dbo.UltimoEstadoDocumento(d.DocumentoID) AS estado
    WHERE 
        u.Nome = 'Departamento Jurídico';
END;

GO
CREATE PROCEDURE dbo.ContarAcoesHistorico
    @DocumentoID INT
AS
BEGIN
    SELECT 
        COUNT(*) AS TotalAcoes
    FROM 
        LogAtividades
    WHERE 
        DocumentoID = @DocumentoID;
END;

GO
CREATE TRIGGER TR_PreventDeleteDocumentos
ON Documentos
INSTEAD OF DELETE
AS
BEGIN
    UPDATE Documentos
    SET Hiden = 1
    FROM Documentos d
    JOIN Deleted del ON d.DocumentoID = del.DocumentoID;
END;

GO
CREATE TRIGGER TR_TrackDocumentChanges
ON Documentos
AFTER INSERT, UPDATE
AS
BEGIN
    -- Declarar uma variável para armazenar o próximo LogID
    DECLARE @NextLogID INT;

    -- Obter o próximo LogID baseado no maior valor atual
    SELECT @NextLogID = ISNULL(MAX(LogID), 0) + 1
    FROM LogAtividades;

    -- Inserir registros no log
    INSERT INTO LogAtividades (LogID, DocumentoID, Acao, DataHora, IntervenienteID)
    SELECT 
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + (@NextLogID - 1) AS LogID,
        i.DocumentoID,
        CASE 
            WHEN NOT EXISTS (SELECT * FROM Deleted) THEN 'Inserido'
            WHEN EXISTS (SELECT * FROM Deleted) THEN 'Atualizado'
        END AS Acao,
        GETDATE() AS DataHora,
        1 AS IntervenienteID -- utilizando '1' para efeitos de teste, CURRENT_USER seria o ideal
    FROM 
        Inserted i;
END;
GO

GO
CREATE TRIGGER TR_BlockchainKeyLogAtividades
ON LogAtividades
AFTER INSERT
AS
BEGIN
    -- Declarar a variável para armazenar a BlockchainKey anterior
    DECLARE @PrevBlockchainKey VARBINARY(256);

    -- Obter a última BlockchainKey antes do novo registro
    SELECT TOP 1 @PrevBlockchainKey = BlockchainKey
    FROM LogAtividades
    WHERE LogID < (SELECT MIN(LogID) FROM Inserted)
    ORDER BY LogID DESC;

    -- Caso não exista registro anterior, usar '1' como salt inicial
    IF @PrevBlockchainKey IS NULL
        SET @PrevBlockchainKey = HASHBYTES('SHA2_256', '1');

    -- Atualizar a BlockchainKey para os novos registros
    UPDATE LogAtividades
    SET BlockchainKey = HASHBYTES(
        'SHA2_256', 
        CAST(i.DocumentoID AS VARCHAR) + 
        i.Acao + 
        CONVERT(VARCHAR, i.DataHora, 121) + 
        CAST(i.IntervenienteID AS VARCHAR) + 
        CONVERT(VARCHAR(MAX), @PrevBlockchainKey, 1)
    )
    FROM LogAtividades l
    JOIN Inserted i ON l.LogID = i.LogID;
END;
GO

--View

CREATE VIEW DocumentosArquivados AS
SELECT 
    d.DocumentoID, 
    d.Descricao, 
    d.DataRecepcao, 
    u.Nome AS UnidadeOrganica
FROM 
    Documentos d
JOIN 
    Estado e ON d.EstadoID = e.EstadoID
JOIN 
    UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
WHERE 
    e.Nome = 'Arquivado';


GO
CREATE VIEW DocumentosUltimos30Dias AS
SELECT 
    d.DocumentoID, 
    d.Descricao, 
    d.DataRecepcao, 
    d.DataHoraInsercao, 
    u.Nome AS UnidadeOrganica
FROM 
    Documentos d
JOIN 
    UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
WHERE 
    d.DataHoraInsercao >= DATEADD(DAY, -30, GETDATE());


GO
CREATE VIEW DocumentosCertidaoNascimento AS
SELECT 
    d.DocumentoID, 
    d.Descricao, 
    d.DataRecepcao, 
    u.Nome AS UnidadeOrganica, 
    e.Nome AS Estado
FROM 
    Documentos d
JOIN 
    TipoDocumento t ON d.TipoID = t.TipoID
JOIN 
    UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
JOIN 
    Estado e ON d.EstadoID = e.EstadoID
WHERE 
    t.Descricao = 'Certidão de Nascimento';

GO
CREATE VIEW DocumentosDepartamentoFinanceiro AS
SELECT 
    d.DocumentoID, 
    d.Descricao, 
    d.DataRecepcao, 
    u.Nome AS UnidadeOrganica, 
    e.Nome AS Estado
FROM 
    Documentos d
JOIN 
    UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
JOIN 
    Estado e ON d.EstadoID = e.EstadoID
WHERE 
    u.Nome = 'Departamento Financeiro';
GO

--Inserts
INSERT INTO TipoDocumento (TipoID, Descricao)
VALUES 
(1, 'Relatório'),
(2, 'Exame Medico'),
(3, 'contrato de casa'),
(4, 'Contrato de carro'),
(5, 'BI'),
(6, 'Certidão de Nascimento');

INSERT INTO Estado (EstadoID, Nome)
VALUES 
(1, 'Em Analise'),
(2, 'Aprovado'),
(3, 'Rejeitado'),
(4, 'Arquivado'),
(5, 'Pendente');

INSERT INTO UnidadeOrganica (UnidadeOrganicaID, Nome)
VALUES 
(1, 'Departamento de Recursos Humanos'),
(2, 'Departamento Financeiro'),
(3, 'Departamento de TI'),
(4, 'Departamento de Marketing'),
(5, 'Departamento de Vendas'),
(6, 'Departamento Jurídico');

INSERT INTO Intervenientes (IntervenienteID, Nome, Tipo, UnidadeOrganicaID)
VALUES 
(1, 'Maria Silva', 'Funcionário', 1),
(2, 'João Souza', 'Funcionário', 2),
(3, 'Ana Costa', 'Funcionário', 3),
(4, 'Pedro Martins', 'Funcionário', 4),
(5, 'Lucas Lopes', 'Funcionário', 1),
(6, 'Fernanda Gomes', 'Funcionário', 2),
(7, 'Roberto Dias', 'Funcionário', 3),
(8, 'Carla Oliveira', 'Funcionário', 4),
(9, 'Ricardo Pereira', 'Funcionário', 1),
(10, 'Sofia Almeida', 'Funcionário', 2);

INSERT INTO Documentos (DocumentoID, TipoID, EstadoID, DataRecepcao,Descricao, UnidadeOrganicaID )
VALUES 
(1, 1, 3, '2023-12-01','Descrição', 1),
(2, 2, 3, '2023-12-02','Descrição', 1),
(3, 3, 2, '2023-12-03','Descrição', 2),
(4, 4, 1, '2023-12-04','Descrição', 2), 
(5, 5, 1, '2023-12-05','Descrição', 3),
(6, 1, 1, '2023-12-06','Descrição', 3), 
(7, 2, 2, '2023-12-07','Descrição', 4), 
(8, 3, 4, '2023-12-08','Descrição', 4),
(9, 4, 1, '2023-12-09','Descrição', 1),
(10, 5, 2, '2023-12-10','Descrição', 1),
(603, 3, 1, '2023-12-25', 'Contrato de Trabalho', 6);

INSERT INTO Faturas (NumeroDocumento, NIPC_Vendedor, NIF_Comprador, DataFatura, ValorTotal)
VALUES
(1001, '501234567', '508765432', '2023-12-01', 1200.00),
(1002, '501234567', '501234321', '2023-12-02', 300.50),
(1003, '502345678', '507654321', '2023-12-03', 450.75),
(1004, '503456789', '506543210', '2023-12-04', 990.99),
(1005, '504567890', '505432109', '2023-12-05', 560.00);

INSERT INTO Certidoes (NumeroDocumento, NomeCertidao, DataExpiracao)
VALUES
(2001, 'Certidão de Nascimento', '2030-01-01'),
(2002, 'Certidão de Casamento', '2040-01-01'),
(2003, 'Certidão de Divórcio', '2035-01-01'),
(2004, 'Certidão de Óbito', '2090-01-01'),
(2005, 'Certidão de Propriedade', '2030-12-31');

INSERT INTO Documentos (DocumentoID, TipoID, EstadoID, DataRecepcao, Descricao,UnidadeOrganicaID, Confidencial)
VALUES
(101, 1, 2, '2023-12-15','Descrição', 1,1),
(102, 2, 1, '2023-12-16','Descrição', 2,2),
(103, 5, 3, '2023-12-17','Descrição', 3,3),
(104, 6, 1, '2023-12-20', 'Certidão de Nascimento de João Silva', 1,4),
(301, 1, 1, '2023-12-10', 'Relatório Financeiro Anual', 2,6),
(302, 2, 2, '2023-12-12', 'Exame de Auditoria Interna', 2,5),
(601, 3, 1, '2023-12-25', 'Contrato de Trabalho', 6,7),
(602, 2, 2, '2023-12-26', 'Parecer Jurídico sobre Licitação', 6,8);

--testar o trigger que esconde ficheiros "apagados"
INSERT INTO Documentos (DocumentoID, TipoID, EstadoID, DataRecepcao, Descricao, UnidadeOrganicaID)
VALUES 
(701, 1, 1, '2023-12-27', 'Documento Visível 1', 1),
(702, 2, 2, '2023-12-28', 'Documento Visível 2', 2);

--testar o trigger que atualiza o historico dos dados dos documentos
INSERT INTO Documentos (DocumentoID, TipoID, EstadoID, DataRecepcao, Descricao, UnidadeOrganicaID)
VALUES (901, 3, 1, '2024-01-01', 'Documento Teste', 1);

INSERT INTO Documentos (DocumentoID, TipoID, EstadoID, DataRecepcao, Descricao, UnidadeOrganicaID)
VALUES 
(902,2,1, '2024-01-01', 'Documento Teste', 1),
(903,3,3,  '2024-01-01 ', 'Documento Teste', 1);

INSERT INTO ArquivoDocumental (ArquivoID, Localizacao, Referencia)
VALUES
(1, 'Prateleira A1', 'ARQ001'),
(2, 'Prateleira B2', 'ARQ002'),
(3, 'Prateleira C3', 'ARQ003'),
(4, 'Arquivo Principal', 'ARQ004'),
(5, 'Arquivo Secundário', 'ARQ005');


INSERT INTO Secretariado (SecretariadoID, Nome)
VALUES
(1, 'Gabinete Administrativo Central'),
(2, 'Secretariado de Projetos'),
(3, 'Secretariado Financeiro'),
(4, 'Secretariado de Recursos Humanos'),
(5, 'Secretariado Jurídico');


INSERT INTO TipoNotificacao (TipoID, Descricao)
VALUES
(1, 'Notificação por E-mail'),
(2, 'Notificação por SMS'),
(3, 'Notificação no Sistema'),
(4, 'Notificação por Carta'),
(5, 'Notificação via App');

INSERT INTO Notificacoes (NotificacaoID, TipoID, Conteudo, DestinatarioID)
VALUES
(1, 1, 'Sua reunião está agendada.', 1),
(2, 2, 'Pagamento pendente.', 2),
(3, 3, 'Atualização importante no sistema.', 3),
(4, 4, 'Receba o relatório impresso.', 4),
(5, 5, 'Confirmação de recebimento disponível.', 5);

INSERT INTO LogAtividades (LogID, DocumentoID, Acao, DataHora, IntervenienteID)
VALUES
(1, 1, 'Criado', '2023-12-01 10:00:00', 1),
(2, 2, 'Atualizado', '2023-12-02 14:30:00', 2),
(3, 3, 'Aprovado', '2023-12-16 16:00:00', 3),
(4, 4, 'Arquivado', '2023-12-04 12:00:00', 4),
(5, 5, 'Rejeitado', '2023-12-05 09:00:00', 5),
(7, 603, 'Criado', '2023-12-25 10:00:00', 7),
(8, 901, 'Criado', '2023-12-25 10:00:00', 8);





SELECT 
    d.DocumentoID, 
    e.Nome AS Estado, 
    d.DataRecepcao, 
    u.Nome AS UnidadeOrganica
FROM 
    Documentos d
JOIN 
    UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
JOIN 
    Estado e ON d.EstadoID = e.EstadoID
WHERE 
    u.UnidadeOrganicaID = 1;



SELECT 
    d.DocumentoID, 
    d.DataRecepcao, 
    u.Nome AS UnidadeOrganica
FROM 
    Documentos d
JOIN 
    UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
JOIN 
    Estado e ON d.EstadoID = e.EstadoID
WHERE 
    e.Nome = 'Em Análise';


SELECT 
    l.Acao, 
    l.DataHora, 
    l.IntervenienteID, 
    e.Nome AS Estado
FROM 
    LogAtividades l
JOIN 
    Documentos d ON l.DocumentoID = d.DocumentoID
JOIN 
    Estado e ON d.EstadoID = e.EstadoID
WHERE 
    l.DocumentoID = 1;


SELECT 
    d.DocumentoID, 
    t.Descricao AS Tipo, 
    e.Nome AS Estado, 
    d.DataRecepcao
FROM 
    Documentos d
JOIN 
    TipoDocumento t ON d.TipoID = t.TipoID
JOIN 
    Estado e ON d.EstadoID = e.EstadoID
WHERE 
    d.DataRecepcao = '2023-12-15';


SELECT 
    d.DocumentoID, 
    e.Nome AS Estado, 
    d.DataRecepcao, 
    u.Nome AS UnidadeOrganica
FROM 
    Documentos d
JOIN 
    UnidadeOrganica u ON d.UnidadeOrganicaID = u.UnidadeOrganicaID
JOIN 
    Estado e ON d.EstadoID = e.EstadoID
WHERE 
    d.DataRecepcao = '2023-12-17';



SELECT LogID, DocumentoID, Acao, DataHora, IntervenienteID
FROM LogAtividades
WHERE CAST(DataHora AS DATE) = '2023-12-16 16:00:00';

SELECT n.NotificacaoID, n.Conteudo, n.TipoID
FROM Notificacoes n
JOIN Documentos d ON n.DestinatarioID = d.DocumentoID
WHERE d.DocumentoID = 4;

SELECT n.NotificacaoID, n.Conteudo, n.TipoID
FROM Notificacoes n
JOIN LogAtividades l ON n.DestinatarioID = l.IntervenienteID
WHERE l.Acao = '';

--Views
SELECT * FROM DocumentosArquivados;
SELECT * FROM DocumentosUltimos30Dias;
SELECT * FROM DocumentosCertidaoNascimento;
SELECT * FROM DocumentosDepartamentoFinanceiro;

--Funções/Procedimentos
SELECT * 
FROM dbo.HistoricoDocumento(8)
ORDER BY DataHora ASC;

SELECT * FROM dbo.UltimoEstadoDocumento(1);

SELECT * FROM dbo.ContagemDocumentosPorEstado();

EXEC dbo.ListarDocumentosConfidenciais;

EXEC dbo.ListarDocumentosJuridico;

EXEC dbo.ContarAcoesHistorico @DocumentoID = 603;

--Trigger's
--(

UPDATE Documentos
SET Descricao = 'Documento Atualizado'
WHERE DocumentoID = 901;

SELECT * FROM LogAtividades WHERE DocumentoID = 901;
--   )

SELECT OBJECT_DEFINITION(OBJECT_ID('TR_BlockchainKeyLogAtividades'));

SELECT LogID, DocumentoID, Acao, DataHora, IntervenienteID, BlockchainKey
FROM LogAtividades;

SELECT *
FROM DocumentosUltimos30Dias


SELECT COUNT(*) as totalDocumentos
FROM Documentos
WHERE EstadoID = 1


