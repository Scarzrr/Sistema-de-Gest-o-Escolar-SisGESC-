```sql
-- ============================================================
-- SISGESC — run_all.sql
-- Script idempotente completo (pode ser executado N vezes)
-- Correções da banca aplicadas integralmente
-- Organização: Domínios | RH | Acadêmico | Financeiro | OLAP | ETL | KPIs
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = 'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION';

-- ============================================================
-- FASE 0 — RESET COMPLETO (idempotência)
-- ============================================================

DROP VIEW  IF EXISTS vw_kpi_inadimplencia;
DROP VIEW  IF EXISTS vw_risco_evasao;

DROP TABLE IF EXISTS fato_financeiro;
DROP TABLE IF EXISTS dim_status_mensalidade;
DROP TABLE IF EXISTS dim_turno;
DROP TABLE IF EXISTS dim_disciplina;
DROP TABLE IF EXISTS dim_aluno;
DROP TABLE IF EXISTS dim_tempo;

DROP TABLE IF EXISTS tb_nota;
DROP TABLE IF EXISTS tb_falta;
DROP TABLE IF EXISTS tb_mensalidade;
DROP TABLE IF EXISTS tb_contrato;
DROP TABLE IF EXISTS tb_matricula;
DROP TABLE IF EXISTS tb_professor_turma;
DROP TABLE IF EXISTS tb_turma;
DROP TABLE IF EXISTS tb_disciplina;
DROP TABLE IF EXISTS tb_folha_pagamento;
DROP TABLE IF EXISTS tb_professor;
DROP TABLE IF EXISTS tb_funcionario;
DROP TABLE IF EXISTS tb_aluno;
DROP TABLE IF EXISTS tb_cargo;
DROP TABLE IF EXISTS tb_status_matricula;
DROP TABLE IF EXISTS tb_status_mensalidade;
DROP TABLE IF EXISTS tb_turno;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- FASE 1 — DDL OLTP
-- Nota de padronização: tabelas OLTP em PascalCase com prefixo tb_
-- tabelas OLAP em snake_case — padrão técnico distinto por camada
-- ============================================================

-- --------------------------
-- Módulo: Domínios
-- CORREÇÃO BANCA: ENUM substitui VARCHAR livre nos status
-- --------------------------

CREATE TABLE tb_status_matricula (
  id   INT NOT NULL AUTO_INCREMENT,
  nome ENUM('Ativa','Trancada','Cancelada','Concluída') NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_status_matricula_nome (nome)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Domínio: situação da matrícula — ENUM evita valores inválidos';

CREATE TABLE tb_status_mensalidade (
  id   INT NOT NULL AUTO_INCREMENT,
  nome ENUM('Pendente','Paga','Atrasada','Cancelada') NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_status_mensalidade_nome (nome)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Domínio: situação de pagamento — ENUM garante conformidade';

CREATE TABLE tb_turno (
  id   INT NOT NULL AUTO_INCREMENT,
  nome ENUM('Matutino','Vespertino','Noturno','Integral') NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_turno_nome (nome)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Domínio: turno da turma';

-- --------------------------
-- Módulo: RH
-- NOVO BANCA: tb_cargo — distinção de cargos obrigatória
-- NOVO BANCA: tb_folha_pagamento — módulo ERP obrigatório
-- --------------------------

CREATE TABLE tb_cargo (
  id    INT          NOT NULL AUTO_INCREMENT,
  nome  VARCHAR(100) NOT NULL,
  nivel ENUM('Operacional','Tático','Estratégico') NOT NULL,
  cbo   VARCHAR(10)  COMMENT 'Código Brasileiro de Ocupações',
  PRIMARY KEY (id),
  UNIQUE KEY uq_cargo_nome (nome)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='RH: cargos com nível hierárquico — exigido pela banca como ERP funcional';

CREATE TABLE tb_funcionario (
  id          CHAR(36)      NOT NULL,
  nome        VARCHAR(150)  NOT NULL,
  cpf         VARCHAR(11)   NOT NULL,
  email       VARCHAR(255)  NOT NULL,
  cargo_id    INT           NOT NULL,
  salario     DECIMAL(10,2) NOT NULL,
  dt_admissao DATE          NOT NULL,
  ativo       TINYINT(1)    NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uq_funcionario_cpf   (cpf),
  UNIQUE KEY uq_funcionario_email (email),
  CONSTRAINT chk_salario   CHECK (salario >= 0),
  CONSTRAINT fk_func_cargo FOREIGN KEY (cargo_id)
    REFERENCES tb_cargo(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='RH: funcionário com cargo, CPF, e-mail e data de admissão';

CREATE TABLE tb_professor (
  id             CHAR(36)     NOT NULL,
  funcionario_id CHAR(36)     NOT NULL,
  especialidade  VARCHAR(150),
  titulacao      ENUM('Graduação','Especialização','Mestrado','Doutorado') NOT NULL DEFAULT 'Graduação',
  PRIMARY KEY (id),
  UNIQUE KEY uq_professor_funcionario (funcionario_id),
  CONSTRAINT fk_professor_funcionario
    FOREIGN KEY (funcionario_id) REFERENCES tb_funcionario(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='RH: professor vinculado a funcionário com titulação';

CREATE TABLE tb_folha_pagamento (
  id               CHAR(36)      NOT NULL,
  funcionario_id   CHAR(36)      NOT NULL,
  competencia      DATE          NOT NULL COMMENT 'Primeiro dia do mês de referência',
  salario_bruto    DECIMAL(10,2) NOT NULL,
  desconto_inss    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  desconto_irrf    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  outros_descontos DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  salario_liquido  DECIMAL(10,2) NOT NULL,
  dt_pagamento     DATE,
  status           ENUM('Aberta','Processada','Paga','Cancelada') NOT NULL DEFAULT 'Aberta',
  PRIMARY KEY (id),
  UNIQUE KEY uq_folha_func_competencia (funcionario_id, competencia),
  CONSTRAINT chk_salario_bruto   CHECK (salario_bruto   >= 0),
  CONSTRAINT chk_salario_liquido CHECK (salario_liquido >= 0),
  CONSTRAINT chk_desc_inss       CHECK (desconto_inss   >= 0),
  CONSTRAINT chk_desc_irrf       CHECK (desconto_irrf   >= 0),
  CONSTRAINT fk_folha_funcionario
    FOREIGN KEY (funcionario_id) REFERENCES tb_funcionario(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='RH: folha de pagamento mensal — módulo ERP obrigatório pela banca';

-- --------------------------
-- Módulo: Acadêmico
-- NOVO BANCA: tb_falta e tb_nota — personalização institucional obrigatória
-- CORREÇÃO BANCA: dt_nascimento adicionada conforme diagrama
-- --------------------------

CREATE TABLE tb_aluno (
  id            CHAR(36)     NOT NULL,
  nome          VARCHAR(150) NOT NULL,
  cpf           VARCHAR(11)  NOT NULL,
  email         VARCHAR(255) NOT NULL,
  dt_nascimento DATE         NOT NULL COMMENT 'Exigido pelo diagrama DER',
  dt_ingresso   DATE         NOT NULL,
  ativo         TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uq_aluno_cpf   (cpf),
  UNIQUE KEY uq_aluno_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Acadêmico: aluno matriculado com data de nascimento conforme DER';

CREATE TABLE tb_disciplina (
  id            CHAR(36)     NOT NULL,
  nome          VARCHAR(150) NOT NULL,
  carga_horaria INT          NOT NULL,
  creditos      INT          NOT NULL DEFAULT 4,
  ementa        TEXT,
  PRIMARY KEY (id),
  CONSTRAINT chk_carga    CHECK (carga_horaria > 0),
  CONSTRAINT chk_creditos CHECK (creditos > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Acadêmico: disciplina ofertada';

CREATE TABLE tb_turma (
  id            CHAR(36) NOT NULL,
  disciplina_id CHAR(36) NOT NULL,
  ano           INT      NOT NULL,
  semestre      INT      NOT NULL,
  turno_id      INT      NOT NULL,
  vagas         INT      NOT NULL DEFAULT 40,
  PRIMARY KEY (id),
  UNIQUE KEY uq_turma_periodo (disciplina_id, ano, semestre, turno_id),
  CONSTRAINT chk_ano      CHECK (ano      >= 2000),
  CONSTRAINT chk_semestre CHECK (semestre IN (1, 2)),
  CONSTRAINT chk_vagas    CHECK (vagas    > 0),
  CONSTRAINT fk_turma_disciplina
    FOREIGN KEY (disciplina_id) REFERENCES tb_disciplina(id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_turma_turno
    FOREIGN KEY (turno_id) REFERENCES tb_turno(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Acadêmico: oferta de disciplina em período e turno';

CREATE TABLE tb_professor_turma (
  id           CHAR(36) NOT NULL,
  professor_id CHAR(36) NOT NULL,
  turma_id     CHAR(36) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_prof_turma (professor_id, turma_id),
  CONSTRAINT fk_profturma_professor
    FOREIGN KEY (professor_id) REFERENCES tb_professor(id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_profturma_turma
    FOREIGN KEY (turma_id) REFERENCES tb_turma(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Acadêmico: N:N professor x turma';

CREATE TABLE tb_matricula (
  id             CHAR(36) NOT NULL,
  aluno_id       CHAR(36) NOT NULL,
  turma_id       CHAR(36) NOT NULL,
  data_matricula DATE     NOT NULL,
  status_id      INT      NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_matricula_aluno_turma (aluno_id, turma_id),
  CONSTRAINT fk_matricula_aluno
    FOREIGN KEY (aluno_id)  REFERENCES tb_aluno(id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_matricula_turma
    FOREIGN KEY (turma_id)  REFERENCES tb_turma(id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_matricula_status
    FOREIGN KEY (status_id) REFERENCES tb_status_matricula(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Acadêmico: vínculo aluno x turma com status';

CREATE TABLE tb_falta (
  id           CHAR(36)     NOT NULL,
  matricula_id CHAR(36)     NOT NULL,
  data_aula    DATE         NOT NULL,
  justificada  TINYINT(1)   NOT NULL DEFAULT 0,
  observacao   VARCHAR(255),
  PRIMARY KEY (id),
  UNIQUE KEY uq_falta_matricula_data (matricula_id, data_aula),
  CONSTRAINT fk_falta_matricula
    FOREIGN KEY (matricula_id) REFERENCES tb_matricula(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Acadêmico: controle de faltas por matrícula — exigido pela banca';

CREATE TABLE tb_nota (
  id            CHAR(36)     NOT NULL,
  matricula_id  CHAR(36)     NOT NULL,
  tipo          ENUM('AV1','AV2','AV3','Recuperação','Final') NOT NULL,
  valor         DECIMAL(4,2) NOT NULL,
  dt_lancamento DATE         NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_nota_matricula_tipo (matricula_id, tipo),
  CONSTRAINT chk_nota_valor CHECK (valor >= 0 AND valor <= 10),
  CONSTRAINT fk_nota_matricula
    FOREIGN KEY (matricula_id) REFERENCES tb_matricula(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Acadêmico: notas por avaliação — exigido pela banca';

-- --------------------------
-- Módulo: Financeiro
-- CORREÇÃO BANCA: ON DELETE RESTRICT + ON UPDATE RESTRICT explícitos
-- garante trilha de auditoria e conformidade institucional
-- campos dt_criacao e dt_atualizacao para rastreabilidade
-- --------------------------

CREATE TABLE tb_contrato (
  id             CHAR(36)      NOT NULL,
  matricula_id   CHAR(36)      NOT NULL,
  data_inicio    DATE          NOT NULL,
  valor_total    DECIMAL(10,2) NOT NULL,
  dt_criacao     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  dt_atualizacao DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_contrato_matricula (matricula_id),
  CONSTRAINT chk_valor_total CHECK (valor_total >= 0),
  CONSTRAINT fk_contrato_matricula
    FOREIGN KEY (matricula_id) REFERENCES tb_matricula(id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Financeiro: contrato 1:1 com matrícula | RESTRICT protege auditoria';

CREATE TABLE tb_mensalidade (
  id              CHAR(36)      NOT NULL,
  contrato_id     CHAR(36)      NOT NULL,
  valor           DECIMAL(10,2) NOT NULL,
  data_vencimento DATE          NOT NULL,
  data_pagamento  DATE,
  status_id       INT           NOT NULL,
  dt_criacao      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  dt_atualizacao  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_parcela (contrato_id, data_vencimento),
  CONSTRAINT chk_valor_mensalidade CHECK (valor >= 0),
  CONSTRAINT fk_mensalidade_contrato
    FOREIGN KEY (contrato_id) REFERENCES tb_contrato(id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_mensalidade_status
    FOREIGN KEY (status_id) REFERENCES tb_status_mensalidade(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Financeiro: parcela mensal | RESTRICT + auditoria de datas';

-- --------------------------
-- Índices — Performance OLTP
-- --------------------------

CREATE INDEX idx_turma_disciplina       ON tb_turma(disciplina_id);
CREATE INDEX idx_turma_turno            ON tb_turma(turno_id);
CREATE INDEX idx_profturma_turma        ON tb_professor_turma(turma_id);
CREATE INDEX idx_matricula_aluno        ON tb_matricula(aluno_id);
CREATE INDEX idx_matricula_turma        ON tb_matricula(turma_id);
CREATE INDEX idx_matricula_status       ON tb_matricula(status_id);
CREATE INDEX idx_falta_matricula        ON tb_falta(matricula_id);
CREATE INDEX idx_falta_data             ON tb_falta(data_aula);
CREATE INDEX idx_nota_matricula         ON tb_nota(matricula_id);
CREATE INDEX idx_mensalidade_contrato   ON tb_mensalidade(contrato_id);
CREATE INDEX idx_mensalidade_vencimento ON tb_mensalidade(data_vencimento);
CREATE INDEX idx_mensalidade_status     ON tb_mensalidade(status_id);
CREATE INDEX idx_folha_funcionario      ON tb_folha_pagamento(funcionario_id);
CREATE INDEX idx_folha_competencia      ON tb_folha_pagamento(competencia);
CREATE INDEX idx_funcionario_cargo      ON tb_funcionario(cargo_id);

-- ============================================================
-- FASE 2 — DML: CARGA IDEMPOTENTE (INSERT IGNORE)
-- ============================================================

INSERT IGNORE INTO tb_status_matricula (nome) VALUES
  ('Ativa'), ('Trancada'), ('Cancelada'), ('Concluída');

INSERT IGNORE INTO tb_status_mensalidade (nome) VALUES
  ('Pendente'), ('Paga'), ('Atrasada'), ('Cancelada');

INSERT IGNORE INTO tb_turno (nome) VALUES
  ('Matutino'), ('Vespertino'), ('Noturno'), ('Integral');

INSERT IGNORE INTO tb_cargo (nome, nivel, cbo) VALUES
  ('Professor',             'Operacional', '2321-05'),
  ('Coordenador Acadêmico', 'Tático',      '1232-15'),
  ('Secretário Escolar',    'Operacional', '4151-05'),
  ('Diretor',               'Estratégico', '1231-05');

INSERT IGNORE INTO tb_funcionario (id, nome, cpf, email, cargo_id, salario, dt_admissao) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'Carlos Mendes',  '99900011100', 'carlos@escola.com',   1, 5800.00, '2020-02-01'),
  ('a1000000-0000-0000-0000-000000000002', 'Fernanda Lima',  '99900022200', 'fernanda@escola.com', 1, 6200.00, '2019-08-01'),
  ('a1000000-0000-0000-0000-000000000003', 'Ricardo Sousa',  '99900033300', 'ricardo@escola.com',  1, 5400.00, '2021-03-01');

INSERT IGNORE INTO tb_professor (id, funcionario_id, especialidade, titulacao) VALUES
  ('b1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'Banco de Dados',         'Mestrado'),
  ('b1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'Engenharia de Software', 'Doutorado'),
  ('b1000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000003', 'Redes de Computadores',  'Especialização');

INSERT IGNORE INTO tb_folha_pagamento (id, funcionario_id, competencia, salario_bruto, desconto_inss, desconto_irrf, salario_liquido, dt_pagamento, status) VALUES
  ('fp000001-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', '2025-03-01', 5800.00, 696.00, 580.00, 4524.00, '2025-03-05', 'Paga'),
  ('fp000001-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', '2025-03-01', 6200.00, 744.00, 620.00, 4836.00, '2025-03-05', 'Paga'),
  ('fp000001-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000003', '2025-03-01', 5400.00, 648.00, 540.00, 4212.00, '2025-03-05', 'Paga');

INSERT IGNORE INTO tb_aluno (id, nome, cpf, email, dt_nascimento, dt_ingresso) VALUES
  ('c1000000-0000-0000-0000-000000000001', 'Ana Paula Souza',   '11122233344', 'ana@email.com',      '2000-05-10', '2025-02-01'),
  ('c1000000-0000-0000-0000-000000000002', 'Bruno Ferreira',    '22233344455', 'bruno@email.com',    '1999-11-22', '2025-02-01'),
  ('c1000000-0000-0000-0000-000000000003', 'Clara Rodrigues',   '33344455566', 'clara@email.com',    '2001-03-15', '2025-02-05'),
  ('c1000000-0000-0000-0000-000000000004', 'Diego Alves',       '44455566677', 'diego@email.com',    '2000-08-30', '2025-02-05'),
  ('c1000000-0000-0000-0000-000000000005', 'Eduarda Costa',     '55566677788', 'eduarda@email.com',  '2001-01-19', '2025-07-10'),
  ('c1000000-0000-0000-0000-000000000006', 'Felipe Martins',    '66677788899', 'felipe@email.com',   '1998-07-04', '2025-07-10'),
  ('c1000000-0000-0000-0000-000000000007', 'Gabriela Nunes',    '77788899900', 'gabriela@email.com', '2002-12-01', '2025-07-15'),
  ('c1000000-0000-0000-0000-000000000008', 'Henrique Carvalho', '88899900011', 'henrique@email.com', '2000-09-25', '2025-07-15');

INSERT IGNORE INTO tb_disciplina (id, nome, carga_horaria, creditos) VALUES
  ('d1000000-0000-0000-0000-000000000001', 'Banco de Dados',         80, 4),
  ('d1000000-0000-0000-0000-000000000002', 'Engenharia de Software', 60, 3),
  ('d1000000-0000-0000-0000-000000000003', 'Redes de Computadores',  60, 3),
  ('d1000000-0000-0000-0000-000000000004', 'Estruturas de Dados',    80, 4);

INSERT IGNORE INTO tb_turma (id, disciplina_id, ano, semestre, turno_id, vagas) VALUES
  ('e1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 2025, 1, 1, 40),
  ('e1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002', 2025, 1, 2, 40),
  ('e1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000003', 2025, 2, 3, 40),
  ('e1000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000004', 2025, 2, 1, 40);

INSERT IGNORE INTO tb_professor_turma (id, professor_id, turma_id) VALUES
  ('f1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001'),
  ('f1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000002'),
  ('f1000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000003'),
  ('f1000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000004');

INSERT IGNORE INTO tb_matricula (id, aluno_id, turma_id, data_matricula, status_id) VALUES
  ('g1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', '2025-02-01', 1),
  ('g1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', '2025-02-01', 1),
  ('g1000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000002', '2025-02-05', 1),
  ('g1000000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000002', '2025-02-05', 1),
  ('g1000000-0000-0000-0000-000000000005', 'c1000000-0000-0000-0000-000000000005', 'e1000000-0000-0000-0000-000000000003', '2025-07-10', 1),
  ('g1000000-0000-0000-0000-000000000006', 'c1000000-0000-0000-0000-000000000006', 'e1000000-0000-0000-0000-000000000003', '2025-07-10', 1),
  ('g1000000-0000-0000-0000-000000000007', 'c1000000-0000-0000-0000-000000000007', 'e1000000-0000-0000-0000-000000000004', '2025-07-15', 1),
  ('g1000000-0000-0000-0000-000000000008', 'c1000000-0000-0000-0000-000000000008', 'e1000000-0000-0000-0000-000000000004', '2025-07-15', 1);

INSERT IGNORE INTO tb_falta (id, matricula_id, data_aula, justificada) VALUES
  ('fa000001-0000-0000-0000-000000000001', 'g1000000-0000-0000-0000-000000000001', '2025-03-10', 0),
  ('fa000001-0000-0000-0000-000000000002', 'g1000000-0000-0000-0000-000000000001', '2025-03-17', 0),
  ('fa000001-0000-0000-0000-000000000003', 'g1000000-0000-0000-0000-000000000002', '2025-03-10', 1),
  ('fa000001-0000-0000-0000-000000000004', 'g1000000-0000-0000-0000-000000000005', '2025-08-12', 0),
  ('fa000001-0000-0000-0000-000000000005', 'g1000000-0000-0000-0000-000000000005', '2025-08-19', 0),
  ('fa000001-0000-0000-0000-000000000006', 'g1000000-0000-0000-0000-000000000005', '2025-08-26', 0);

INSERT IGNORE INTO tb_nota (id, matricula_id, tipo, valor, dt_lancamento) VALUES
  ('no000001-0000-0000-0000-000000000001', 'g1000000-0000-0000-0000-000000000001', 'AV1',        7.50, '2025-04-01'),
  ('no000001-0000-0000-0000-000000000002', 'g1000000-0000-0000-0000-000000000001', 'AV2',        8.00, '2025-06-01'),
  ('no000001-0000-0000-0000-000000000003', 'g1000000-0000-0000-0000-000000000002', 'AV1',        5.00, '2025-04-01'),
  ('no000001-0000-0000-0000-000000000004', 'g1000000-0000-0000-0000-000000000002', 'AV2',        4.50, '2025-06-01'),
  ('no000001-0000-0000-0000-000000000005', 'g1000000-0000-0000-0000-000000000002', 'Recuperação',6.00, '2025-06-15'),
  ('no000001-0000-0000-0000-000000000006', 'g1000000-0000-0000-0000-000000000005', 'AV1',        3.00, '2025-09-01'),
  ('no000001-0000-0000-0000-000000000007', 'g1000000-0000-0000-0000-000000000005', 'AV2',        4.00, '2025-11-01');

INSERT IGNORE INTO tb_contrato (id, matricula_id, data_inicio, valor_total) VALUES
  ('h1000000-0000-0000-0000-000000000001', 'g1000000-0000-0000-0000-000000000001', '2025-02-01', 2400.00),
  ('h1000000-0000-0000-0000-000000000002', 'g1000000-0000-0000-0000-000000000002', '2025-02-01', 2400.00),
  ('h1000000-0000-0000-0000-000000000003', 'g1000000-0000-0000-0000-000000000003', '2025-02-05', 1800.00),
  ('h1000000-0000-0000-0000-000000000004', 'g1000000-0000-0000-0000-000000000004', '2025-02-05', 1800.00),
  ('h1000000-0000-0000-0000-000000000005', 'g1000000-0000-0000-0000-000000000005', '2025-07-10', 2400.00),
  ('h1000000-0000-0000-0000-000000000006', 'g1000000-0000-0000-0000-000000000006', '2025-07-10', 2400.00),
  ('h1000000-0000-0000-0000-000000000007', 'g1000000-0000-0000-0000-000000000007', '2025-07-15', 1800.00),
  ('h1000000-0000-0000-0000-000000000008', 'g1000000-0000-0000-0000-000000000008', '2025-07-15', 1800.00);

-- status: 1=Pendente 2=Paga 3=Atrasada 4=Cancelada
INSERT IGNORE INTO tb_mensalidade (id, contrato_id, valor, data_vencimento, status_id) VALUES
  ('i1000000-0000-0000-0000-000000000001', 'h1000000-0000-0000-0000-000000000001', 800.00, '2025-03-01', 2),
  ('i1000000-0000-0000-0000-000000000002', 'h1000000-0000-0000-0000-000000000001', 800.00, '2025-04-01', 2),
  ('i1000000-0000-0000-0000-000000000003', 'h1000000-0000-0000-0000-000000000001', 800.00, '2025-05-01', 3),
  ('i1000000-0000-0000-0000-000000000004', 'h1000000-0000-0000-0000-000000000002', 800.00, '2025-03-01', 2),
  ('i1000000-0000-0000-0000-000000000005', 'h1000000-0000-0000-0000-000000000002', 800.00, '2025-04-01', 2),
  ('i1000000-0000-0000-0000-000000000006', 'h1000000-0000-0000-0000-000000000002', 800.00, '2025-05-01', 2),
  ('i1000000-0000-0000-0000-000000000007', 'h1000000-0000-0000-0000-000000000003', 600.00, '2025-03-05', 2),
  ('i1000000-0000-0000-0000-000000000008', 'h1000000-0000-0000-0000-000000000003', 600.00, '2025-04-05', 3),
  ('i1000000-0000-0000-0000-000000000009', 'h1000000-0000-0000-0000-000000000003', 600.00, '2025-05-05', 1),
  ('i1000000-0000-0000-0000-000000000010', 'h1000000-0000-0000-0000-000000000004', 600.00, '2025-03-05', 2),
  ('i1000000-0000-0000-0000-000000000011', 'h1000000-0000-0000-0000-000000000004', 600.00, '2025-04-05', 2),
  ('i1000000-0000-0000-0000-000000000012', 'h1000000-0000-0000-0000-000000000004', 600.00, '2025-05-05', 2),
  ('i1000000-0000-0000-0000-000000000013', 'h1000000-0000-0000-0000-000000000005', 800.00, '2025-08-10', 2),
  ('i1000000-0000-0000-0000-000000000014', 'h1000000-0000-0000-0000-000000000005', 800.00, '2025-09-10', 1),
  ('i1000000-0000-0000-0000-000000000015', 'h1000000-0000-0000-0000-000000000005', 800.00, '2025-10-10', 1),
  ('i1000000-0000-0000-0000-000000000016', 'h1000000-0000-0000-0000-000000000006', 800.00, '2025-08-10', 2),
  ('i1000000-0000-0000-0000-000000000017', 'h1000000-0000-0000-0000-000000000006', 800.00, '2025-09-10', 3),
  ('i1000000-0000-0000-0000-000000000018', 'h1000000-0000-0000-0000-000000000006', 800.00, '2025-10-10', 1),
  ('i1000000-0000-0000-0000-000000000019', 'h1000000-0000-0000-0000-000000000007', 600.00, '2025-08-15', 2),
  ('i1000000-0000-0000-0000-000000000020', 'h1000000-0000-0000-0000-000000000007', 600.00, '2025-09-15', 2),
  ('i1000000-0000-0000-0000-000000000021', 'h1000000-0000-0000-0000-000000000007', 600.00, '2025-10-15', 1),
  ('i1000000-0000-0000-0000-000000000022', 'h1000000-0000-0000-0000-000000000008', 600.00, '2025-08-15', 2),
  ('i1000000-0000-0000-0000-000000000023', 'h1000000-0000-0000-0000-000000000008', 600.00, '2025-09-15', 2),
  ('i1000000-0000-0000-0000-000000000024', 'h1000000-0000-0000-0000-000000000008', 600.00, '2025-10-15', 1);

-- Verificação de idempotência — resultado deve ser igual em toda reexecução
SELECT 'tb_status_matricula'  AS tabela, COUNT(*) AS total FROM tb_status_matricula
UNION ALL SELECT 'tb_status_mensalidade', COUNT(*) FROM tb_status_mensalidade
UNION ALL SELECT 'tb_turno',              COUNT(*) FROM tb_turno
UNION ALL SELECT 'tb_cargo',              COUNT(*) FROM tb_cargo
UNION ALL SELECT 'tb_funcionario',        COUNT(*) FROM tb_funcionario
UNION ALL SELECT 'tb_professor',          COUNT(*) FROM tb_professor
UNION ALL SELECT 'tb_folha_pagamento',    COUNT(*) FROM tb_folha_pagamento
UNION ALL SELECT 'tb_aluno',              COUNT(*) FROM tb_aluno
UNION ALL SELECT 'tb_disciplina',         COUNT(*) FROM tb_disciplina
UNION ALL SELECT 'tb_turma',              COUNT(*) FROM tb_turma
UNION ALL SELECT 'tb_professor_turma',    COUNT(*) FROM tb_professor_turma
UNION ALL SELECT 'tb_matricula',          COUNT(*) FROM tb_matricula
UNION ALL SELECT 'tb_falta',              COUNT(*) FROM tb_falta
UNION ALL SELECT 'tb_nota',               COUNT(*) FROM tb_nota
UNION ALL SELECT 'tb_contrato',           COUNT(*) FROM tb_contrato
UNION ALL SELECT 'tb_mensalidade',        COUNT(*) FROM tb_mensalidade;

-- ============================================================
-- FASE 3 — OPERAÇÕES OLTP
-- ============================================================

-- 3.1 SELECT simples — alunos ativos
SELECT id, nome, cpf, email, dt_nascimento, dt_ingresso
FROM tb_aluno WHERE ativo = 1 ORDER BY nome;

-- 3.1 SELECT simples — professores com cargo, titulação e salário
SELECT f.nome AS professor, c.nome AS cargo,
       p.especialidade, p.titulacao, f.salario
FROM tb_professor p
JOIN tb_funcionario f ON f.id = p.funcionario_id
JOIN tb_cargo       c ON c.id = f.cargo_id
ORDER BY f.nome;

-- 3.1 SELECT simples — mensalidades com aluno, disciplina e status
SELECT a.nome AS aluno, d.nome AS disciplina,
       m.valor, m.data_vencimento, m.data_pagamento, sm.nome AS status
FROM tb_mensalidade m
JOIN tb_contrato c            ON c.id  = m.contrato_id
JOIN tb_matricula mt          ON mt.id = c.matricula_id
JOIN tb_aluno a               ON a.id  = mt.aluno_id
JOIN tb_turma t               ON t.id  = mt.turma_id
JOIN tb_disciplina d          ON d.id  = t.disciplina_id
JOIN tb_status_mensalidade sm ON sm.id = m.status_id
ORDER BY a.nome, m.data_vencimento;

-- 3.1 SELECT simples — notas por aluno e disciplina
SELECT a.nome AS aluno, d.nome AS disciplina,
       n.tipo, n.valor, n.dt_lancamento
FROM tb_nota n
JOIN tb_matricula mt ON mt.id = n.matricula_id
JOIN tb_aluno a      ON a.id  = mt.aluno_id
JOIN tb_turma t      ON t.id  = mt.turma_id
JOIN tb_disciplina d ON d.id  = t.disciplina_id
ORDER BY a.nome, d.nome, n.tipo;

-- 3.1 SELECT simples — faltas por aluno
SELECT a.nome AS aluno, d.nome AS disciplina,
       COUNT(*)                      AS total_faltas,
       SUM(f.justificada)            AS faltas_justificadas,
       COUNT(*) - SUM(f.justificada) AS faltas_injustificadas
FROM tb_falta f
JOIN tb_matricula mt ON mt.id = f.matricula_id
JOIN tb_aluno a      ON a.id  = mt.aluno_id
JOIN tb_turma t      ON t.id  = mt.turma_id
JOIN tb_disciplina d ON d.id  = t.disciplina_id
GROUP BY a.nome, d.nome
ORDER BY total_faltas DESC;

-- 3.2 Subselect com agregação — alunos que pagaram mais de R$ 1.500
SELECT a.nome, a.email
FROM tb_aluno a
WHERE a.id IN (
  SELECT mt.aluno_id
  FROM tb_mensalidade m
  JOIN tb_contrato c   ON c.id  = m.contrato_id
  JOIN tb_matricula mt ON mt.id = c.matricula_id
  WHERE m.status_id = 2
  GROUP BY mt.aluno_id
  HAVING SUM(m.valor) > 1500
);

-- 3.2 Subselect correlacionado — disciplinas com mais de 1 aluno
SELECT d.nome AS disciplina, d.carga_horaria
FROM tb_disciplina d
WHERE (
  SELECT COUNT(DISTINCT mt.aluno_id)
  FROM tb_matricula mt
  JOIN tb_turma t ON t.id = mt.turma_id
  WHERE t.disciplina_id = d.id
) > 1;

-- 3.3 Transação com ROLLBACK
START TRANSACTION;
  INSERT INTO tb_mensalidade (id, contrato_id, valor, data_vencimento, status_id)
  VALUES (UUID(), 'h1000000-0000-0000-0000-000000000001', 999.00, '2025-12-01', 1);
ROLLBACK;
SELECT * FROM tb_mensalidade WHERE data_vencimento = '2025-12-01'; -- NÃO deve existir

-- 3.4 Transação com COMMIT
START TRANSACTION;
  INSERT INTO tb_mensalidade (id, contrato_id, valor, data_vencimento, status_id)
  VALUES ('i9900000-0000-0000-0000-000000000099', 'h1000000-0000-0000-0000-000000000001', 850.00, '2025-11-01', 1);
  UPDATE tb_contrato SET valor_total = valor_total + 850.00
  WHERE id = 'h1000000-0000-0000-0000-000000000001';
COMMIT;
SELECT * FROM tb_mensalidade WHERE id = 'i9900000-0000-0000-0000-000000000099'; -- DEVE existir

-- 3.5 Transação múltipla com ROLLBACK — diferencial de nota
START TRANSACTION;
  UPDATE tb_mensalidade SET status_id = 2
  WHERE id = 'i1000000-0000-0000-0000-000000000009';
  UPDATE tb_contrato SET valor_total = valor_total - 600.00
  WHERE id = 'h1000000-0000-0000-0000-000000000003';
ROLLBACK;
SELECT status_id FROM tb_mensalidade
WHERE id = 'i1000000-0000-0000-0000-000000000009'; -- deve continuar 1 (Pendente)

-- ============================================================
-- FASE 4A — DDL OLAP (Modelo Estrela)
-- Nota: snake_case nas tabelas OLAP por convenção de DW
-- ============================================================

CREATE TABLE dim_tempo (
  sk_tempo      INT         NOT NULL AUTO_INCREMENT,
  data_completa DATE        NOT NULL,
  ano           INT         NOT NULL,
  semestre      INT         NOT NULL,
  mes           INT         NOT NULL,
  nome_mes      VARCHAR(20) NOT NULL,
  trimestre     VARCHAR(10) NOT NULL,
  dia           INT         NOT NULL,
  PRIMARY KEY (sk_tempo),
  UNIQUE KEY uq_dim_tempo_data (data_completa)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE dim_aluno (
  sk_aluno BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_oltp  CHAR(36)        NOT NULL,
  nome     VARCHAR(150)    NOT NULL,
  cpf      VARCHAR(11)     NOT NULL,
  email    VARCHAR(255)    NOT NULL,
  PRIMARY KEY (sk_aluno),
  UNIQUE KEY uq_dim_aluno_oltp (id_oltp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE dim_disciplina (
  sk_disciplina  INT          NOT NULL AUTO_INCREMENT,
  id_oltp        CHAR(36)     NOT NULL,
  nome           VARCHAR(150) NOT NULL,
  carga_horaria  INT          NOT NULL,
  ano_turma      INT          NOT NULL,
  semestre_turma INT          NOT NULL,
  PRIMARY KEY (sk_disciplina),
  UNIQUE KEY uq_dim_disc (id_oltp, ano_turma, semestre_turma)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE dim_turno (
  sk_turno INT         NOT NULL AUTO_INCREMENT,
  id_oltp  INT         NOT NULL,
  nome     VARCHAR(50) NOT NULL,
  PRIMARY KEY (sk_turno),
  UNIQUE KEY uq_dim_turno_oltp (id_oltp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE dim_status_mensalidade (
  sk_status INT         NOT NULL AUTO_INCREMENT,
  id_oltp   INT         NOT NULL,
  nome      VARCHAR(50) NOT NULL,
  PRIMARY KEY (sk_status),
  UNIQUE KEY uq_dim_status_oltp (id_oltp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE fato_financeiro (
  sk_fato             INT             NOT NULL AUTO_INCREMENT,
  sk_tempo            INT             NOT NULL,
  sk_aluno            BIGINT UNSIGNED NOT NULL,
  sk_disciplina       INT             NOT NULL,
  sk_turno            INT             NOT NULL,
  sk_status           INT             NOT NULL,
  valor_mensalidade   DECIMAL(10,2)   NOT NULL,
  valor_contrato      DECIMAL(10,2)   NOT NULL,
  qtd_parcelas        INT             NOT NULL,
  id_mensalidade_oltp CHAR(36)        NOT NULL,
  PRIMARY KEY (sk_fato),
  UNIQUE KEY uq_fato_oltp (id_mensalidade_oltp),
  CONSTRAINT fk_fato_tempo      FOREIGN KEY (sk_tempo)      REFERENCES dim_tempo(sk_tempo),
  CONSTRAINT fk_fato_aluno      FOREIGN KEY (sk_aluno)      REFERENCES dim_aluno(sk_aluno),
  CONSTRAINT fk_fato_disciplina FOREIGN KEY (sk_disciplina) REFERENCES dim_disciplina(sk_disciplina),
  CONSTRAINT fk_fato_turno      FOREIGN KEY (sk_turno)      REFERENCES dim_turno(sk_turno),
  CONSTRAINT fk_fato_status     FOREIGN KEY (sk_status)     REFERENCES dim_status_mensalidade(sk_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_fato_tempo      ON fato_financeiro(sk_tempo);
CREATE INDEX idx_fato_aluno      ON fato_financeiro(sk_aluno);
CREATE INDEX idx_fato_disciplina ON fato_financeiro(sk_disciplina);
CREATE INDEX idx_fato_turno      ON fato_financeiro(sk_turno);
CREATE INDEX idx_fato_status     ON fato_financeiro(sk_status);

-- ============================================================
-- FASE 4B — ETL: OLTP → OLAP
-- ============================================================

INSERT IGNORE INTO dim_tempo (data_completa, ano, semestre, mes, nome_mes, trimestre, dia)
SELECT DISTINCT
  m.data_vencimento,
  YEAR(m.data_vencimento),
  IF(MONTH(m.data_vencimento) <= 6, 1, 2),
  MONTH(m.data_vencimento),
  DATE_FORMAT(m.data_vencimento, '%M'),
  CONCAT('T', QUARTER(m.data_vencimento)),
  DAY(m.data_vencimento)
FROM tb_mensalidade m;

INSERT IGNORE INTO dim_aluno (id_oltp, nome, cpf, email)
SELECT id, nome, cpf, email FROM tb_aluno;

INSERT IGNORE INTO dim_disciplina (id_oltp, nome, carga_horaria, ano_turma, semestre_turma)
SELECT DISTINCT d.id, d.nome, d.carga_horaria, t.ano, t.semestre
FROM tb_disciplina d
JOIN tb_turma t ON t.disciplina_id = d.id;

INSERT IGNORE INTO dim_turno (id_oltp, nome)
SELECT id, nome FROM tb_turno;

INSERT IGNORE INTO dim_status_mensalidade (id_oltp, nome)
SELECT id, nome FROM tb_status_mensalidade;

INSERT IGNORE INTO fato_financeiro (
  sk_tempo, sk_aluno, sk_disciplina, sk_turno, sk_status,
  valor_mensalidade, valor_contrato, qtd_parcelas, id_mensalidade_oltp
)
SELECT
  dt.sk_tempo,
  da.sk_aluno,
  dd.sk_disciplina,
  dtu.sk_turno,
  ds.sk_status,
  m.valor,
  c.valor_total,
  (SELECT COUNT(*) FROM tb_mensalidade m2 WHERE m2.contrato_id = c.id),
  m.id
FROM tb_mensalidade m
JOIN tb_contrato c              ON c.id  = m.contrato_id
JOIN tb_matricula mt            ON mt.id = c.matricula_id
JOIN tb_turma t                 ON t.id  = mt.turma_id
JOIN dim_tempo   dt             ON dt.data_completa   = m.data_vencimento
JOIN dim_aluno   da             ON da.id_oltp          = mt.aluno_id
JOIN dim_disciplina dd          ON dd.id_oltp           = t.disciplina_id
                               AND dd.ano_turma          = t.ano
                               AND dd.semestre_turma     = t.semestre
JOIN dim_turno   dtu            ON dtu.id_oltp           = t.turno_id
JOIN dim_status_mensalidade ds  ON ds.id_oltp             = m.status_id;

-- ============================================================
-- FASE 4C — VALIDAÇÃO ETL
-- ============================================================

SELECT 'OLTP — soma mensalidades'    AS origem, SUM(valor)             AS total FROM tb_mensalidade
UNION ALL
SELECT 'OLAP — soma fato_financeiro',            SUM(valor_mensalidade)         FROM fato_financeiro;

SELECT 'OLTP — count mensalidades'   AS origem, COUNT(*) AS total FROM tb_mensalidade
UNION ALL
SELECT 'OLAP — count fato_financeiro',           COUNT(*)                       FROM fato_financeiro;

-- ============================================================
-- FASE 4D — CONSULTAS ANALÍTICAS OLAP
-- ============================================================

-- Faturamento por mês
SELECT dt.nome_mes, dt.ano,
       SUM(f.valor_mensalidade) AS faturamento,
       COUNT(*)                 AS qtd_parcelas
FROM fato_financeiro f
JOIN dim_tempo dt ON dt.sk_tempo = f.sk_tempo
GROUP BY dt.nome_mes, dt.ano, dt.mes
ORDER BY dt.ano, dt.mes;

-- Faturamento por disciplina
SELECT dd.nome AS disciplina, dd.semestre_turma AS semestre,
       SUM(f.valor_mensalidade)   AS faturamento,
       COUNT(DISTINCT f.sk_aluno) AS qtd_alunos
FROM fato_financeiro f
JOIN dim_disciplina dd ON dd.sk_disciplina = f.sk_disciplina
GROUP BY dd.nome, dd.semestre_turma
ORDER BY faturamento DESC;

-- Inadimplência por aluno
SELECT da.nome AS aluno,
       COUNT(*) AS parcelas_atrasadas,
       SUM(f.valor_mensalidade) AS valor_em_atraso
FROM fato_financeiro f
JOIN dim_aluno da              ON da.sk_aluno  = f.sk_aluno
JOIN dim_status_mensalidade ds ON ds.sk_status = f.sk_status
WHERE ds.nome = 'Atrasada'
GROUP BY da.nome
ORDER BY valor_em_atraso DESC;

-- Faturamento por turno e semestre
SELECT dtu.nome AS turno, dt.semestre, dt.ano,
       SUM(f.valor_mensalidade) AS faturamento
FROM fato_financeiro f
JOIN dim_turno dtu ON dtu.sk_turno = f.sk_turno
JOIN dim_tempo dt  ON dt.sk_tempo  = f.sk_tempo
GROUP BY dtu.nome, dt.semestre, dt.ano
ORDER BY dt.ano, dt.semestre, faturamento DESC;

-- ============================================================
-- FASE 5 — VIEWS DE KPI (BI/IA) — sugestão da banca atendida
-- ============================================================

-- KPI 1: Inadimplência real vs projetada por aluno
CREATE OR REPLACE VIEW vw_kpi_inadimplencia AS
SELECT
  a.id                                        AS aluno_id,
  a.nome                                      AS aluno,
  a.email,
  d.nome                                      AS disciplina,
  COUNT(m.id)                                 AS parcelas_atrasadas,
  SUM(m.valor)                                AS valor_total_em_atraso,
  MIN(m.data_vencimento)                      AS vencimento_mais_antigo,
  DATEDIFF(CURDATE(), MIN(m.data_vencimento)) AS dias_maior_atraso
FROM tb_mensalidade m
JOIN tb_status_mensalidade sm ON sm.id  = m.status_id AND sm.nome = 'Atrasada'
JOIN tb_contrato c            ON c.id   = m.contrato_id
JOIN tb_matricula mt          ON mt.id  = c.matricula_id
JOIN tb_aluno a               ON a.id   = mt.aluno_id
JOIN tb_turma t               ON t.id   = mt.turma_id
JOIN tb_disciplina d          ON d.id   = t.disciplina_id
GROUP BY a.id, a.nome, a.email, d.nome
ORDER BY valor_total_em_atraso DESC;

-- KPI 2: Previsão de evasão — cruza status_id, carga_horaria, notas e faltas
CREATE OR REPLACE VIEW vw_risco_evasao AS
SELECT
  a.id                                                          AS aluno_id,
  a.nome                                                        AS aluno,
  d.nome                                                        AS disciplina,
  d.carga_horaria,
  COALESCE(AVG(n.valor), 0)                                     AS media_notas,
  COUNT(DISTINCT fa.id)                                         AS total_faltas,
  ROUND(COUNT(DISTINCT fa.id) * 100.0 / NULLIF(d.carga_horaria, 0), 1) AS percentual_faltas,
  SUM(CASE WHEN sm.nome = 'Atrasada' THEN 1 ELSE 0 END)        AS parcelas_atrasadas,
  (
    (CASE WHEN COALESCE(AVG(n.valor), 0) < 5 THEN 3 ELSE 0 END) +
    (CASE WHEN COUNT(DISTINCT fa.id) * 100.0 / NULLIF(d.carga_horaria, 0) > 25 THEN 3 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN sm.nome = 'Atrasada' THEN 1 ELSE 0 END) > 0 THEN 2 ELSE 0 END)
  )                                                             AS score_risco,
  CASE
    WHEN (
      (CASE WHEN COALESCE(AVG(n.valor), 0) < 5 THEN 3 ELSE 0 END) +
      (CASE WHEN COUNT(DISTINCT fa.id) * 100.0 / NULLIF(d.carga_horaria, 0) > 25 THEN 3 ELSE 0 END) +
      (CASE WHEN SUM(CASE WHEN sm.nome = 'Atrasada' THEN 1 ELSE 0 END) > 0 THEN 2 ELSE 0 END)
    ) >= 6 THEN 'ALTO'
    WHEN (
      (CASE WHEN COALESCE(AVG(n.valor), 0) < 5 THEN 3 ELSE 0 END) +
      (CASE WHEN COUNT(DISTINCT fa.id) * 100.0 / NULLIF(d.carga_horaria, 0) > 25 THEN 3 ELSE 0 END) +
      (CASE WHEN SUM(CASE WHEN sm.nome = 'Atrasada' THEN 1 ELSE 0 END) > 0 THEN 2 ELSE 0 END)
    ) >= 3 THEN 'MÉDIO'
    ELSE 'BAIXO'
  END                                                           AS nivel_risco
FROM tb_matricula mt
JOIN tb_aluno a       ON a.id  = mt.aluno_id
JOIN tb_turma t       ON t.id  = mt.turma_id
JOIN tb_disciplina d  ON d.id  = t.disciplina_id
LEFT JOIN tb_nota n            ON n.matricula_id  = mt.id
LEFT JOIN tb_falta fa          ON fa.matricula_id = mt.id
LEFT JOIN tb_contrato c        ON c.matricula_id  = mt.id
LEFT JOIN tb_mensalidade m     ON m.contrato_id   = c.id
LEFT JOIN tb_status_mensalidade sm ON sm.id        = m.status_id
GROUP BY a.id, a.nome, d.nome, d.carga_horaria
ORDER BY score_risco DESC, media_notas ASC;

-- Consulta das views
SELECT * FROM vw_kpi_inadimplencia;
SELECT * FROM vw_risco_evasao;

-- ============================================================
-- FASE 6 — PERFORMANCE: EXPLAIN
-- ============================================================

EXPLAIN
SELECT a.nome, m.valor, m.data_vencimento, sm.nome AS status
FROM tb_mensalidade m
JOIN tb_contrato c            ON c.id  = m.contrato_id
JOIN tb_matricula mt          ON mt.id = c.matricula_id
JOIN tb_aluno a               ON a.id  = mt.aluno_id
JOIN tb_status_mensalidade sm ON sm.id = m.status_id
WHERE m.data_vencimento BETWEEN '2025-03-01' AND '2025-05-31'
  AND m.status_id = 3;

-- ============================================================
-- FIM — SISGESC run_all.sql
-- ============================================================
```