import boto3
import json

def main(): 
    print("📡 INICIANDO CONEXIÓN A N. VIRGINIA...\n")
    try:
        sts = boto3.client('sts')
        identity = sts.get_caller_identity()
        user_arn = identity['Arn']
        print(f"🔐 Identidad Verificada: {user_arn}\n")
    except Exception as e:
        print(f"❌ Error al verificar identidad: {e}")
        return

    print("\n🔍 Escaneando Grupos de Seguridad (Security Groups)...")
    ec2 = boto3.client('ec2', region_name='us-east-1')
    response = ec2.describe_security_groups()
    alert_count = 0

    for group in response['SecurityGroups']:
        group_id = group['GroupId']
        for rule in group['IpPermissions']:
            from_port = rule.get('FromPort', 'All Ports')
            for ip_range in rule.get('IpRanges', []):
                if ip_range['CidrIp'] == '0.0.0.0/0':
                    print(f"¡ALERTA! El grupo {group_id} tiene el puerto {from_port} abierto al mundo.")
                    alert_count += 1

    if alert_count == 0:
        print("✅ No se encontraron grupos de seguridad con puertos abiertos al mundo.")
    else:
        print(f"\n⚠️ Escaneo Completo: {alert_count} alertas encontradas.") 
    print("\n Guardando resultados en 'security_groups_report.json'...")
    reporte = {
        "status": "Success",
        "user" : user_arn,
        "total_alerts": alert_count,
    }
    with open('security_groups_report.json', 'w') as f:
        json.dump(reporte, f, indent=4)             
if __name__ == "__main__":
    main()