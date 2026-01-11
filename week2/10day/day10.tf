# =============================================================================
# PERMISSIONS BOUNDARY POLICY
# =============================================================================
# Esta policy actúa como "límite máximo" de permisos
# Aunque un rol tenga más permisos, nunca podrá exceder lo que el boundary permite

resource "aws_iam_policy" "restricted_boundary" { # Define un recurso de tipo política de IAM llamado "restricted_boundary"
  name        = "RestrictedBoundary" # Asigna el nombre "RestrictedBoundary" a la política en AWS
  description = "Permissions Boundary - Permite S3, Logs y Lambda List; deniega IAM y Billing" # Descripción del propósito

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ✅ ALLOW: Operaciones permitidas (El área de juego segura)
      {
        Sid      = "AllowedServices"
        Effect   = "Allow"
        Action   = [
          "s3:*",
          "logs:*",
          "lambda:ListFunctions" # Agregado común para devs
        ]
        Resource = "*"
      },
      
      # ❌ DENY EXPLÍCITO: Bloquear escalada de privilegios (IAM)
      # Esto evita que el Dev cree su propio usuario Admin.
      {
        Sid      = "DenyIAM" # Identificador
        Effect   = "Deny" # Deniega explícitamente (prioridad alta)
        Action   = "iam:*" # Todas las acciones de IAM (evita escalada de privilegios)
        Resource = "*" # Todos los recursos IAM
      },
      # ❌ DENY EXPLÍCITO: Bloquear acceso a Billing (Facturación)
      {
        Sid      = "DenyBilling" # Identificador
        Effect   = "Deny" # Deniega
        Action   = [ # Lista de acciones de facturación a bloquear
          "aws-portal:*",    # Portal antiguo
          "billing:*",       # Facturación
          "cost-explorer:*", # Explorador de costos
          "budgets:*",       # Presupuestos
          "payments:*",      # Pagos
          "tax:*"            # Impuestos
        ]
        Resource = "*" # Todos los recursos
      }
    ]
  })
}

# =============================================================================
# IAM USER: JuniorDev
# =============================================================================

resource "aws_iam_user" "junior_dev" { # Define el usuario IAM "junior_dev"
  name = "JuniorDev" # Nombre del usuario en AWS

  tags = { # Etiquetas para organización
    Environment = "Development" # Entorno
    Role        = "Junior Developer" # Rol funcional
  }
}

# =============================================================================
# USER POLICY (Permiso para asumir el rol)
# =============================================================================
# CONCEPTO: Para asumir un rol, se necesitan dos "SÍ":
# 1. El Rol debe confiar en el Usuario (Trust Policy).
# 2. El Usuario debe tener permiso para llamar al Rol (Identity Policy).
# Este bloque faltaba antes. Sin esto, el usuario recibe "Access Denied".

resource "aws_iam_user_policy" "junior_dev_assume_permission" { # Define una política inline adjunta al usuario
  name = "AllowAssumeJuniorRole" # Nombre de la política
  user = aws_iam_user.junior_dev.name # Referencia al usuario creado arriba

  policy = jsonencode({ # Definición de la política
    Version = "2012-10-17" # Versión
    Statement = [ # Declaraciones
      {
        Sid      = "AllowAssumption" # Identificador
        Effect   = "Allow" # Permite
        Action   = "sts:AssumeRole" # Acción de asumir rol
        Resource = aws_iam_role.junior_dev_role.arn # Restringe a solo poder asumir este rol específico
      }
    ]
  })
}

# =============================================================================
# 4. IAM ROLE (LA MÁSCARA) 🎭
# =============================================================================
# CONCEPTO: El rol es un sombrero que el usuario se pone.
# Aquí aplicamos el BOUNDARY. Es lo que hace que este rol sea "seguro".

resource "aws_iam_role" "junior_dev_role" { # Define el rol de IAM
  name = "JuniorDevRole" # Nombre del rol

  # 🔒 PERMISSIONS BOUNDARY: Limita los permisos máximos del rol
  permissions_boundary = aws_iam_policy.restricted_boundary.arn # Aplica la política de frontera creada arriba

  # Trust Policy: Quién puede asumir este rol
  assume_role_policy = jsonencode({ # Política de confianza
    Version = "2012-10-17" # Versión
    Statement = [ # Declaraciones
      {
        Effect = "Allow" # Permite
        Principal = { # Entidad permitida
          AWS = aws_iam_user.junior_dev.arn # Solo el usuario JuniorDev puede asumir este rol
        }
        Action = "sts:AssumeRole" # Acción de asumir rol
      }
    ]
  })

  tags = { # Etiquetas
    Environment = "Development" # Entorno
    Boundary    = "RestrictedBoundary" # Marca de boundary
  }
}

# =============================================================================
# 5. ROLE PERMISSIONS (LAS TAREAS) 📋
# =============================================================================
# CONCEPTO: Estos son los permisos funcionales.
# NOTA: Aunque aquí pusiéramos "Effect: Allow, Action: *", el Boundary
# (Paso 1) bloquearía IAM y Billing de todos modos. Esa es la magia.

resource "aws_iam_role_policy" "junior_dev_policy" { # Política inline adjunta al rol
  name = "JuniorDevWorkPolicy" # Nombre de la política
  role = aws_iam_role.junior_dev_role.id # Referencia al rol

  policy = jsonencode({ # Definición JSON
    Version = "2012-10-17" # Versión
    Statement = [ # Permisos
      {
        Sid      = "AllowS3Access" # Acceso S3
        Effect   = "Allow" # Permite
        Action   = "s3:*" # Todo S3
        Resource = "*" # Todo recurso
      },
      {
        Sid      = "AllowLogsAccess" # Acceso Logs
        Effect   = "Allow" # Permite
        Action   = "logs:*" # Todo Logs
        Resource = "*" # Todo recurso
      }
    ]
  })
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "test_instruction" { # Instrucción para probar
  value = "Para probar: Configura perfil 'JuniorDev' y ejecuta: aws sts assume-role --role-arn ${aws_iam_role.junior_dev_role.arn} --role-session-name TestSession"
}

output "boundary_policy_arn" { # Output del ARN de la política
  description = "ARN de la Permissions Boundary Policy"
  value       = aws_iam_policy.restricted_boundary.arn
}

output "junior_dev_user_arn" { # Output del ARN del usuario
  description = "ARN del usuario JuniorDev"
  value       = aws_iam_user.junior_dev.arn
}

output "junior_dev_role_arn" { # Output del ARN del rol
  description = "ARN del rol con boundary aplicado"
  value       = aws_iam_role.junior_dev_role.arn
}