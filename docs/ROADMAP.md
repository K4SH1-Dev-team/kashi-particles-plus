# Roadmap

## Onde estamos

**v1.0.0** — paridade completa com o Snowstorm 3.2.2 para o formato `.particle.json`, endurecido
para uso em produção em workspaces diferentes da de desenvolvimento. Ver histórico completo
abaixo.

## Próximas fases

### Fase 3 — Melhorias e correções
A definir com o usuário quando começar.

### Fase 4 — Porte para MCreator 2026.2
Novos geradores: NeoForge 1.21.8, 26.1 e 26.2. Hoje o plugin implementa só o gerador
`neoforge-1.21.1` (ver [ARCHITECTURE.md](ARCHITECTURE.md)) — portar significa duplicar (ou
parametrizar) `src/neoforge-1.21.1/` para cada novo par gerador/versão, e revalidar que o
`runtime/` compila contra cada API de Minecraft alvo (o MoLang engine em `core/` não depende de
Minecraft, então essa parte deve migrar sem atrito).

---

## Histórico: o plano de paridade Snowstorm

O que segue é o plano original que levou o plugin de um importador parcial a paridade completa
com o Snowstorm, usando os 279 arquivos de um resource pack Bedrock real (mantido fora do
repositório — ver `docs/DEVELOPMENT.md`) como banco de provas. Preservado como registro de por que
cada peça existe; todas as fases abaixo estão concluídas.

**Objetivo original:** o plugin aceita **tudo** que o Snowstorm 3.2.2 exporta e reproduz
**idêntico**.

### Onde o plano começou (17 de 20 componentes usados no pack já implementados)

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

### As lacunas que motivaram as fases

| Lacuna | Arquivos | Sintoma no jogo |
|---|---|---|
| **`curves`** (aba Variables & Curves) | **84** | `v.size` lê **0** → partícula de tamanho zero, **invisível** |
| **`emitter_local_space`** | **114** | não herda posição/rotação/velocidade do emissor |
| **`events` + `emitter_lifetime_events`** | 28 (324 nós) | efeitos encadeados nunca disparam |
| **`particle_motion_collision`** | 7 | atravessa blocos |
| `particle_kill_plane` | 0 no pack | — (paridade Snowstorm) |
| `expire_if_in_blocks` / `_not_in_blocks` | 0 no pack | — (paridade Snowstorm) |
| `emitter_shape_custom` / `entity_aabb` | 0 no pack | — (paridade Snowstorm) |

A lacuna de curvas era a mais grave: 42 arquivos escreviam `variable.size` numa curva e 40 liam
`v.size` no campo Size — sem curvas, isso valia 0, e a partícula desaparecia sem explicação.

### As 7 fases (todas concluídas)

1. **Curvas** *(84 arquivos)* — `particle_effect.curves` com os 4 tipos do Bedrock (`linear`,
   `catmull_rom`, `bezier`, `bezier_chain`), reavaliadas por tick no escopo certo
   (emissor vs partícula). Implementado em `core/.../CurveSampler.java`.
2. **`emitter_local_space`** *(114 arquivos)* — `position`/`rotation`/`velocity`: partículas
   passam a acompanhar a entidade que disparou o efeito. É o que liga o campo **Aim** das
   procedures ao interior do efeito.
3. **Eventos** *(28 arquivos, 324 nós)* — mapa `events` + gatilhos `emitter_lifetime_events`/
   `particle_lifetime_events`, nós `particle_effect`, `sound_effect`, `expression`, `log`,
   `randomize`, `sequence`. Implementado em `runtime/.../KashiEventRunner.java`. Um efeito que
   dispara outro exige que o outro também esteja importado — o wizard avisa disso.
4. **Colisão e expiração** — `particle_motion_collision` (7 arquivos), `kill_plane`,
   `expire_if_in_blocks`/`expire_if_not_in_blocks`.
5. **Restos de paridade** — `emitter_shape_custom`, `emitter_shape_entity_aabb`, e
   `particles_alpha` corrigido para alpha *test* (recorte) em vez de blend.
6. **Robustez** — cinco correções: `facing()` desconhecido degradava para exceção (rejeitando o
   arquivo inteiro) em vez de cair em `rotate_xyz` com aviso; `initialSpeed` escalar sendo lido
   como velocidade por eixo em vez de escalar-na-direção; `MolangCompiler` com array de slots
   curto quando algo compilava depois do primeiro contexto; `blendOf()` decidindo por substring
   do nome do material (um material customizado caía em alpha por sorte); identificadores
   duplicados no pack.
7. **Diagnóstico semântico** — `ParticleDiagnostics` (usado pelo validador em lote e pelo wizard):
   tamanho ou alpha zero em toda a vida, `max_frame` além do que a folha comporta, variável lida
   sem nunca ser definida, identificador duplicado.

### Situação ao fechar a paridade (22/07/2026)

Todas as fases concluídas. Dos 279 arquivos do pack de prova: 279 carregam, 0 rejeitados, nenhum
componente declarado por eles é ignorado. O que sobrou depois disso era autoria do pack, não bug
do plugin: 23 arquivos com `max_frame` além da folha, 1 com uma expressão MoLang inválida
(`math.round` com 2 argumentos numa função de 1), 1 lendo uma variável nunca definida.

### V1.0.0 — de "funciona nesta workspace" a produção portável (agosto/2026)

Depois da paridade, um teste em massa (todos os efeitos de um pack disparados juntos) revelou dois
problemas de *teste*, não de motor: alguns efeitos tinham offset de emissor muito acima do
jogador (conteúdo autoral, não bug), e efeitos curtos/rápidos perdiam o frame sob o lag severo de
disparar dezenas de efeitos pesados no mesmo tick (comportamento inerente do desacoplamento
tick/frame do Minecraft sob carga, não específico deste plugin). A decisão foi parar de perseguir
esses casos e, em vez disso, endurecer o plugin para produção:

- `KashiParticleType.overrideLimiter = true` — sem isso, efeitos disparados a mais de ~15-30
  blocos do jogador nunca criavam o emissor (achado via decompilação de
  `LevelRenderer.addParticle`).
- `tools/optimize-textures.py` — recompressão PNG sem perdas (re-deflate + paleta indexada,
  verificado byte-a-byte/pixel-a-pixel antes de aceitar).
- `ParticleDiagnostics.volumeFindings` — aviso no wizard quando um efeito importado estimaria
  mais de 2000 partículas.
- Tooltips dos blocos de procedure com aviso operacional sobre disparar muitos efeitos pesados no
  mesmo tick.
- `KashiDebugCommand` — nome do comando passou a incorporar o `MODID` (`/kashiparticle_<modid>`),
  evitando colisão se dois mods construídos com este plugin coexistirem num modpack.
- `particle.json.ftl` — passou a degradar graciosamente (em vez de travar a geração do mod
  inteiro) quando um elemento é salvo sem nunca importar um `.particle.json`.
- Testado do zero numa segunda workspace MCreator (modid diferente) para confirmar portabilidade
  de verdade, não só validação estática.
