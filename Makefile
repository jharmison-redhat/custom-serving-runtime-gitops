SHELL := /bin/bash

.EXPORT_ALL_VARIABLES:

KUBECONFIG = /tmp/custom-serving-demo

.PHONY: all
all: bootstrap

.PHONY: login
login:
	rm -f $(KUBECONFIG)
	$(MAKE) $(KUBECONFIG)

$(KUBECONFIG): creds.env
	@source creds.env; oc login -u "$$USER" -p "$$PASSWORD" "$$CLUSTER"

.PHONY: bootstrap
bootstrap: $(KUBECONFIG)
	oc apply -k bootstrap/ || \
		while [ "$$(oc get subscription.operators -n openshift-operators openshift-gitops-operator -ojsonpath='{.status.state}')" != "AtLatestKnown" ]; do sleep 5; done; oc apply -k bootstrap/ || \
		while ! oc get namespace openshift-gitops; do sleep 5; done; oc apply -k bootstrap/

.PHONY: credentials
credentials: $(KUBECONFIG)
	@if [ -f creds.env ]; then \
		source creds.env; \
		echo "Username: $$USER"; \
		echo "Password: $$PASSWORD"; \
		echo; \
	fi
	@if oc get route -n openshift-gitops openshift-gitops-server &>/dev/null; then \
		echo "GitOps: https://$$(oc get route -n openshift-gitops openshift-gitops-server -ojsonpath='{.status.ingress[0].host}')"; \
	fi
	@if oc get route -n redhat-ods-applications rhods-dashboard &>/dev/null; then \
		echo "RHODS: https://$$(oc get route -n redhat-ods-applications rhods-dashboard -ojsonpath='{.status.ingress[0].host}')"; \
	fi
