# Plano de paridade total com o Snowstorm

Objetivo: o plugin aceita **tudo** que o Snowstorm 3.2.2 exporta e reproduz **idêntico**, com os 279
arquivos de `ds rp/particles` como banco de provas.

Os números abaixo saíram de uma varredura real dos 279 arquivos (não são estimativas).

---

## Onde estamos

### Já implementado (17 de 20 componentes usados no pack)

| Componente | Arquivos |
|---|---|
| `particle_lifetime_expression` | 279 |
| `particle_appearance_billboard` (10 facings, flipbook) | 279 |
| `particle_initial_speed` | 277 |
| `particle_motion_dynamic` | 266 |
| `emitter_lifetime_once` | 257 |
| `particle_appearance_tinting` (gradiente + expressão) | 252 |
| `emitter_rate_instant` | 216 |
| `particle_initial_spin` | 196 |
| `emitter_shape_point` | 143 |
| `emitter_shape_disc` | 87 |
| `emitter_rate_steady` | 63 |
| `emitter_shape_sphere` | 48 |
| `emitter_lifetime_expression` | 11 |
| `emitter_lifetime_looping` | 9 |
| `particle_appearance_lighting` | 8 |
| `particle_motion_parametric` | 1 |
| `emitter_shape_box` | 1 |

### Faltando — e o que cada lacuna custa

| Lacuna | Arquivos | Sintoma no jogo |
|---|---|---|
| **`curves`** (aba Variables & Curves) | **84** | `v.size` lê **0** → partícula de tamanho zero, **invisível** |
| **`emitter_local_space`** | **114** | não herda posição/rotação/velocidade do emissor |
| **`events` + `emitter_lifetime_events`** | 28 (324 nós) | efeitos encadeados nunca disparam |
| **`particle_motion_collision`** | 7 | atravessa blocos |
| `particle_kill_plane` | 0 no pack | — (paridade Snowstorm) |
| `expire_if_in_blocks` / `_not_in_blocks` | 0 no pack | — (paridade Snowstorm) |
| `emitter_shape_custom` / `entity_aabb` | 0 no pack | — (paridade Snowstorm) |

O item nº 1 é o mais grave e explica boa parte dos "não aparece nada": 42 arquivos escrevem
`variable.size` numa curva e 40 leem `v.size` no campo Size. Sem curvas, isso vale 0.

---

## Fases

### Fase 1 — Curvas *(84 arquivos)*
`particle_effect.curves` com os 4 tipos do Bedrock: `linear`, `catmull_rom`, `bezier`,
`bezier_chain`. Cada curva tem `input` (MoLang), `horizontal_range` e `nodes`, e escreve num
`variable.*`. Precisa reavaliar por tick, no escopo certo (emissor vs partícula).
Tipos presentes no pack: `catmull_rom` (73) e `linear` (27).

### Fase 2 — `emitter_local_space` *(114 arquivos)*
`position` / `rotation` / `velocity`. Com `position: true` as partículas acompanham o emissor;
`rotation: true` faz o offset e a velocidade nascerem no referencial girado do emissor — é o que
liga o campo **Aim** das procedures ao interior do efeito.

### Fase 3 — Eventos *(28 arquivos, 324 nós)*
Mapa `events` + gatilhos `emitter_lifetime_events` (creation, expiration, travel_distance,
travel_distance_events, timeline) e `particle_lifetime_events` (creation, expiration, timeline).
Nós: `particle_effect` (`emitter` / `emitter_bound` / `particle` / `particle_with_velocity`),
`sound_effect`, `expression`, `log`, `randomize`, `sequence`.
**Implicação de import:** um efeito que dispara outro exige que o outro também esteja importado —
o wizard vai precisar avisar (ou importar em cascata).

### Fase 4 — Colisão e expiração
`particle_motion_collision` (7 arquivos: `collision_drag`, `coefficient_of_restitution`,
`collision_radius`, `expire_on_contact`), `kill_plane`, `expire_if_in_blocks`,
`expire_if_not_in_blocks`.

### Fase 5 — Restos de paridade
`emitter_shape_custom`, `emitter_shape_entity_aabb`, material `particles_alpha` como **alpha test**
(recorte) em vez de blend — hoje os dois caem no mesmo render type (5 arquivos).

### Fase 6 — Robustez (varredura de bugs e fragilidades)
Itens já identificados por leitura de código, a confirmar um a um:

1. `facing()` **lança exceção** em modo desconhecido → rejeita o arquivo inteiro. Deve degradar para
   `rotate_xyz` com aviso.
2. `initialSpeed` escalar vira `Vec3Expr(s, s, s)`; o runtime precisa saber que é escalar-na-direção,
   não velocidade por eixo.
3. `MolangCompiler.newContext()` dimensiona pelos slots vistos **até então** — se algo compilar depois
   do primeiro contexto, o array fica curto.
4. `blendOf()` decide por substring do nome do material; material custom com nome inesperado cai
   silenciosamente em alpha.
5. Identificadores duplicados no pack (`sound:form1a` aparece em 3 arquivos).

### Fase 7 — Diagnóstico para o teste em massa
Antes do teste em massa vale ter um validador que já responda **por que** um efeito some, sem abrir o
Minecraft. Estender `tools/validate-particles.ps1` com avisos semânticos:

- tamanho resolve para 0 em toda a vida;
- alpha 0 em toda a vida;
- `max_frame` além do que a folha comporta (`largura / step_UV`) → quadros transparentes no fim;
- `variable.*` lido sem nunca ser definido (nem curva, nem initialization);
- identificador duplicado.

---

## Situação final (22/07/2026)

**Todas as fases concluídas.** Dos 279 arquivos: 279 carregam, 0 rejeitados, e **nenhum componente
declarado por eles é ignorado** — a seção "componentes ignorados" do validador ficou vazia.

Sobra para o teste em massa, tudo achado pelo próprio validador e nenhum deles é bug do plugin:

| Achado | Arquivos | O que é |
|---|---|---|
| `max-frame-past-sheet` | 23 | `max_frame` maior do que a folha comporta — os últimos quadros ficam transparentes. Erro de autoria. |
| `expression-invalid` | 1 | `math.round(0.5,1.5)` em `slash_base` — 2 argumentos numa função de 1. Não vai carregar (mas não derruba os outros). |
| `variable-undefined` | 1 | `zidanpedit` lê `variable.size1`/`size2` que nada define. |

## Ordem de execução

1. ~~Fase 1 (curvas) — destrava 84 arquivos~~ **FEITA**
2. ~~Fase 2 (local space) — 114 arquivos~~ **FEITA**
3. Fase 7 (validador semântico) — para o teste em massa render diagnóstico, não só "não apareceu"
4. Fase 6 (robustez)
5. Fase 3 (eventos)
6. Fases 4 e 5 (paridade final)

Depois das fases 1 e 2, dos 279 arquivos do pack só restam **17** com eventos e **7** com colisão
declarando algo que o plugin ignora.
