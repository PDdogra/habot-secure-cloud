# ==============================================================================
# Candidate Name: Pranav Dogra
# Email: pranavdograa@gmail.com
# Module: Student Onboarding Discrete Condition Yes/No (DCYN) Serializer
# ==============================================================================
from rest_framework import serializers


class StudentOnboardingSerializer(serializers.Serializer):
    """
    Validates incoming student onboarding data payloads and converts
    conditional attributes into Discrete Condition Yes/No (DCYN) binary logic.
    """

    student_id = serializers.CharField(max_length=50, required=True)
    first_name = serializers.CharField(max_length=100, required=True)
    last_name = serializers.CharField(max_length=100, required=True)
    age = serializers.IntegerField(min_value=3, max_value=21, required=True)
    has_learning_disability = serializers.BooleanField(required=True)
    guardian_email = serializers.EmailField(required=True)
    requires_lsa_support = serializers.BooleanField(required=True)

    def validate_guardian_email(self, value):
        allowed_domains = ("@gmail.com", "@habot.io", "@yahoo.com", "@outlook.com")
        if not value.lower().endswith(allowed_domains):
            raise serializers.ValidationError(
                "Domain specified in guardian email address is not permitted."
            )
        return value

    def to_representation(self, instance):
        """
        Converts boolean fields into explicit DCYN binary output (1 for Yes, 0 for No).
        """
        ret = super().to_representation(instance)
        ret["has_learning_disability_dcyn"] = (
            1 if instance.get("has_learning_disability") else 0
        )
        ret["requires_lsa_support_dcyn"] = (
            1 if instance.get("requires_lsa_support") else 0
        )
        return ret
