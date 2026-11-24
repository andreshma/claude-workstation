# menu-claude-mas.tmux — submenú: más atajos y comandos de Claude (se envían a la pestaña actual).
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] Claude · más comandos " -x C -y C \
  "Lista de tareas de Claude (Ctrl+T)"        d "send-keys C-t" \
  "Editar el prompt en el editor (Ctrl+G)"    g "send-keys C-g" \
  "Guardar o recuperar borrador (Ctrl+S)"     x "send-keys C-s" \
  "Modo rápido sí/no (Alt+O)"                 f "send-keys M-o" \
  "Detener subagentes en segundo plano"       K "send-keys C-x C-k" \
  "Redibujar la pantalla (Ctrl+L)"            l "send-keys C-l" \
  '' \
  "Estado y cuenta (/status)"                 i "send-keys /status Enter" \
  "Uso y límites (/usage)"                    u "send-keys /usage Enter" \
  "Servidores MCP (/mcp)"                     m "send-keys /mcp Enter" \
  "Esfuerzo (/effort)"                        E "send-keys /effort Enter" \
  '' \
  "‹ Volver"                                  BSpace "source-file ~/.config/tmux-claude/menu-claude.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
