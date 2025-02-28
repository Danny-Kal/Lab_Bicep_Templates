import { Override } from "framer"

export function ButtonOverride(): Override {
    return {
        onClick: async () => {
            console.log("Button clicked!")

            // URL of your Azure Function
            const url =
                "https://simpleltest4framerbutton.azurewebsites.net/api/HttpTrigger1"

            // Data to send in the request body (matching your cURL command)
            const data = {
                subscriptionId: "2a53178d-15e9-4710-b06f-e289b4e672c0", // Replace with your subscription ID
                resourceGroup: "FunctionAppTests", // Replace with your resource group name
                templateUrl:
                    "https://raw.githubusercontent.com/Danny-Kal/Lab_Bicep_Templates/refs/heads/main/1stlabdraft.json", // Replace with your template URL
            }

            try {
                // Send the POST request to the Azure Function
                const response = await fetch(url, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify(data), // Convert the data to JSON
                })

                // Check if the request was successful
                if (!response.ok) {
                    const errorDetails = await response.text()
                    console.error(
                        "Request failed with status:",
                        response.status,
                        "Details:",
                        errorDetails
                    )
                } else {
                    const result = await response.text()
                    console.log("Response from Azure Function:", result)
                }
            } catch (error) {
                console.error("Error sending request:", error)
            }
        },
    }
}
