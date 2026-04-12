-- =========================
-- EXTENSÕES
-- =========================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =========================
-- DOMÍNIOS
-- =========================
CREATE TABLE StatusMatricula (
  id   SERIAL PRIMARY KEY,
  nome VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE StatusMensalidade (
  id   SERIAL PRIMARY KEY,
  nome VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE Turno (
  id   SERIAL PRIMARY KEY,
  nome VARCHAR(50) UNIQUE NOT NULL
);

-- =========================
-- DADOS INICIAIS
-- =========================
INSERT INTO StatusMatricula (nome) VALUES
  ('Ativa'), ('Trancada'), ('Cancelada'), ('Concluída');

INSERT INTO StatusMensalidade (nome) VALUES
  ('Pendente'), ('Paga'), ('Atrasada'), ('Cancelada');

INSERT INTO Turno (nome) VALUES
  ('Matutino'), ('Vespertino'), ('Noturno'), ('Integral');

-- =========================
-- ENTIDADES
-- =========================
CREATE TABLE Funcionario (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome VARCHAR(150) NOT NULL,
  salario NUMERIC(10,2) NOT NULL CHECK (salario >= 0)
);

CREATE TABLE Professor (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id UUID UNIQUE NOT NULL
    REFERENCES Funcionario(id) ON DELETE RESTRICT,
  especialidade VARCHAR(150)
);

CREATE TABLE Aluno (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome VARCHAR(150) NOT NULL,
  cpf VARCHAR(11) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL
);

CREATE TABLE Disciplina (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome VARCHAR(150) NOT NULL,
  carga_horaria INT NOT NULL CHECK (carga_horaria > 0)
);

-- =========================
-- TURMA
-- =========================
CREATE TABLE Turma (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  disciplina_id UUID NOT NULL
    REFERENCES Disciplina(id) ON DELETE RESTRICT,
  ano INT NOT NULL CHECK (ano >= 2000),
  semestre INT NOT NULL CHECK (semestre IN (1,2)),
  turno_id INT NOT NULL
    REFERENCES Turno(id) ON DELETE RESTRICT,

  CONSTRAINT unique_turma_periodo
  UNIQUE (disciplina_id, ano, semestre, turno_id)
);

-- =========================
-- PROFESSOR ↔ TURMA
-- =========================
CREATE TABLE ProfessorTurma (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  professor_id UUID NOT NULL
    REFERENCES Professor(id) ON DELETE RESTRICT,
  turma_id UUID NOT NULL
    REFERENCES Turma(id) ON DELETE RESTRICT,

  UNIQUE (professor_id, turma_id)
);

-- =========================
-- MATRÍCULA
-- =========================
CREATE TABLE Matricula (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  aluno_id UUID NOT NULL
    REFERENCES Aluno(id) ON DELETE RESTRICT,
  turma_id UUID NOT NULL
    REFERENCES Turma(id) ON DELETE RESTRICT,
  data_matricula DATE NOT NULL DEFAULT CURRENT_DATE,
  status_id INT NOT NULL
    REFERENCES StatusMatricula(id) ON DELETE RESTRICT,

  UNIQUE (aluno_id, turma_id)
);

-- =========================
-- CONTRATO
-- =========================
CREATE TABLE Contrato (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  matricula_id UUID UNIQUE NOT NULL
    REFERENCES Matricula(id) ON DELETE RESTRICT,
  data_inicio DATE NOT NULL DEFAULT CURRENT_DATE,
  valor_total NUMERIC(10,2) NOT NULL CHECK (valor_total >= 0)
);

-- =========================
-- MENSALIDADE
-- =========================
CREATE TABLE Mensalidade (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contrato_id UUID NOT NULL
    REFERENCES Contrato(id) ON DELETE RESTRICT,
  valor NUMERIC(10,2) NOT NULL CHECK (valor >= 0),
  data_vencimento DATE NOT NULL,
  status_id INT NOT NULL
    REFERENCES StatusMensalidade(id) ON DELETE RESTRICT,

  CONSTRAINT unique_parcela
  UNIQUE (contrato_id, data_vencimento)
);

-- =========================
-- ÍNDICES
-- =========================
CREATE INDEX idx_turma_disciplina       ON Turma(disciplina_id);
CREATE INDEX idx_turma_turno            ON Turma(turno_id);
CREATE INDEX idx_professorturma_turma   ON ProfessorTurma(turma_id);
CREATE INDEX idx_matricula_aluno        ON Matricula(aluno_id);
CREATE INDEX idx_matricula_turma        ON Matricula(turma_id);
CREATE INDEX idx_mensalidade_contrato   ON Mensalidade(contrato_id);
CREATE INDEX idx_mensalidade_vencimento ON Mensalidade(data_vencimento);