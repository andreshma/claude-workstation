# Estándares de trabajo

Si tu organización o el repo tienen una guía de ingeniería propia, esa manda: léela antes de proponer o revisar
código. Si algo de aquí choca con esa guía o con el README del repo, dímelo antes de actuar.

## Precedencia
Ley → contrato y políticas del cliente → políticas de la organización → estándar y guías → decisiones del proyecto
(ADR/README). Toda desviación queda explícita (motivo, riesgo, dueño, fecha de revisión) en ADR, README o ticket.

## Cómo trabajar conmigo
- Responde en el idioma en que escribo. Decisión primero, luego razonamiento y trade-offs.
- Tablas y código antes que párrafos; no expliques conceptos básicos.
- Ante ambigüedad de diseño: recomendación + al menos una alternativa con trade-offs.
- Antes de un cambio en la nube (az, terraform, kubectl) muestra el comando y la suscripción o contexto activo.

## Git
- Conventional Commits `type(scope): description` en imperativo (feat, fix, chore, docs, refactor, test,
  ci, perf, style, build), salvo que el repo defina otra convención.
- Commits atómicos. Nunca `Co-authored-by` (la configuración ya lo bloquea).
- Estrategia de ramas la que diga el README (trunk-based o GitFlow); PR con revisor hacia main o release;
  commits firmados si el cliente lo exige.

## Documentación
- Decisión no trivial → ADR (Status, Context, Decision, Consequences, Alternatives). Arquitectura → C4.
  Requisitos no funcionales → FURPS+. Nada de artefactos pesados en tareas triviales.
- Repos: README (propósito, setup, variables, runbook) y CHANGELOG (Keep a Changelog).
- Código: documentación idiomática del lenguaje; superficie pública y el porqué no obvio, sin comentarios redundantes.

## Calidad
- Pirámide de tests; todo código nuevo con sus tests. Obligatorio en auth, pagos, permisos y migraciones
  destructivas. Cobertura como confianza en el cambio, no como porcentaje.
- Datos de prueba no productivos y anonimizados. DoD explícita en PRs; contract testing entre servicios.

## Seguridad e IA
- OWASP Top 10, ASVS y LLM Top 10 como checklist; threat modeling en diseño.
- Secretos en Key Vault: nunca en código, prompts, fixtures ni logs. Least privilege.
- Agentes y herramientas con el mismo rigor que un usuario privilegiado (authz, allowlist, sandbox);
  humano en el ciclo para acciones destructivas.
- El código generado se revisa como cualquier PR; no sustituye la revisión de seguridad ni las pruebas.

## Cloud y CI/CD
IaC primero, sin ClickOps en prod; tagging env, owner, cost-center, project; multi-AZ en prod.
Pipeline Lint → SAST → Test → Build → DAST → Deploy → Smoke; rollback y SLOs antes de producción.

## Archivos
Office o PDF → Markdown (MarkItDown o pandoc) antes de procesar; si no hay herramienta, pídeme el archivo convertido.

## Obsidian
Tengo un vault de Obsidian accesible con el CLI `obsidian` (search, read, tasks, daily:read…).
Úsalo para mis notas, tareas y notas diarias; MemPalace es para decisiones e historial de proyectos.
Escribe en el vault solo si te lo pido. Nunca borres, publiques ni ejecutes código ahí.

## Sandbox: comandos de nube y red
- Ejecuta `az`, `kubectl`, `gh`, `terraform` y `git push/pull/fetch/clone/ls-remote` solos en la llamada:
  sin `|`, `&&`, `cd`, redirección a archivo ni `$(...)`. Si no, el sandbox los atrapa y fallan.
- Filtra con `--query` y `-o tsv|json` en lugar de `| jq`; usa `git -C <ruta>` en lugar de `cd`.
