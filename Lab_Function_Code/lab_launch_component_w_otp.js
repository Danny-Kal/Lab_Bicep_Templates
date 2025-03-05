import { addPropertyControls, ControlType } from "framer"
import React, { useState, useEffect } from "react"

export function AzureFunctionButton(props) {
    // State for response data, loading status, and errors
    const [responseData, setResponseData] = useState(null)
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState(null)

    // State for TOTP code
    const [totpCode, setTotpCode] = useState(null)
    const [totpExpiry, setTotpExpiry] = useState(null)
    const [secondsRemaining, setSecondsRemaining] = useState(0)
    const [refreshingCode, setRefreshingCode] = useState(false)

    // Countdown timer effect
    useEffect(() => {
        if (!secondsRemaining) return

        const timer = setInterval(() => {
            setSecondsRemaining((prev) => {
                if (prev <= 1) {
                    clearInterval(timer)
                    return 0
                }
                return prev - 1
            })
        }, 1000)

        return () => clearInterval(timer)
    }, [secondsRemaining])

    // Function to refresh TOTP code
    const refreshTotpCode = async () => {
        if (!responseData || !responseData.username) {
            return
        }

        setRefreshingCode(true)

        try {
            const response = await fetch(
                "https://simpleltest4framerbutton.azurewebsites.net/api/totptriggertest",
                {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({
                        username: responseData.username,
                    }),
                }
            )

            if (!response.ok) {
                const errorData = await response.json()
                throw new Error(
                    errorData.error || "Failed to refresh verification code"
                )
            }

            const data = await response.json()

            setTotpCode(data.code)
            setTotpExpiry(new Date(data.expiryTime))
            setSecondsRemaining(data.secondsRemaining)
        } catch (error) {
            setError(error.message)
        } finally {
            setRefreshingCode(false)
        }
    }

    // Function to handle the main button click
    const handleClick = async () => {
        setLoading(true)
        setError(null)

        // URL of your Azure Function
        const url =
            "https://simpleltest4framerbutton.azurewebsites.net/api/HttpTrigger1?"

        // Data to send in the request body
        const data = {
            subscriptionId: "2a53178d-15e9-4710-b06f-e289b4e672c0",
            resourceGroup: "FunctionAppTests",
            templateUrl:
                "https://raw.githubusercontent.com/Danny-Kal/Lab_Bicep_Templates/refs/heads/main/1stlabdraft.json",
        }

        try {
            // Send the POST request to the Azure Function
            const response = await fetch(url, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                },
                body: JSON.stringify(data),
            })

            if (!response.ok) {
                const errorData = await response.json()
                throw new Error(
                    errorData.error || `Request failed: ${response.status}`
                )
            }

            // Parse the response
            const result = await response.json()

            // Set all data
            setResponseData(result)

            // Set TOTP info if provided
            if (result.totpCode) {
                setTotpCode(result.totpCode)
                setTotpExpiry(new Date(result.totpExpiryTime))
                setSecondsRemaining(result.totpSecondsRemaining)
            }
        } catch (error) {
            setError(error.message)
        } finally {
            setLoading(false)
        }
    }

    return (
        <div style={containerStyle}>
            {/* Button to trigger the Azure Function */}
            <button
                onClick={handleClick}
                style={buttonStyle}
                disabled={loading}
            >
                {loading ? "Launching Lab..." : "Launch Lab Environment"}
            </button>

            {/* Display the response data */}
            {responseData && (
                <div style={responseStyle}>
                    <h3>Lab Environment Ready!</h3>
                    <p>
                        <strong>Username:</strong> {responseData.username}
                    </p>
                    <p>
                        <strong>Password:</strong> {responseData.password}
                    </p>

                    {/* MFA Code Section */}
                    <div style={mfaCodeStyle}>
                        <div style={mfaHeaderStyle}>
                            <h4>MFA Verification Code:</h4>
                            <button
                                onClick={refreshTotpCode}
                                style={refreshButtonStyle}
                                disabled={refreshingCode}
                            >
                                {refreshingCode
                                    ? "Refreshing..."
                                    : "Refresh Code"}
                            </button>
                        </div>

                        {totpCode ? (
                            <div style={codeDisplayStyle}>
                                <span style={codeStyle}>{totpCode}</span>
                                <div style={progressBarContainer}>
                                    <div
                                        style={{
                                            ...progressBarStyle,
                                            width: `${(secondsRemaining / 30) * 100}%`,
                                            backgroundColor:
                                                secondsRemaining < 10
                                                    ? "#ff4d4d"
                                                    : "#4CAF50",
                                        }}
                                    />
                                </div>
                                <span style={timerStyle}>
                                    {secondsRemaining > 0
                                        ? `${secondsRemaining}s remaining`
                                        : "Code expired - please refresh"}
                                </span>
                            </div>
                        ) : (
                            <p>
                                No verification code available. Click 'Refresh
                                Code'.
                            </p>
                        )}
                    </div>
                </div>
            )}

            {/* Display error message if any */}
            {error && <p style={errorStyle}>Error: {error}</p>}
        </div>
    )
}

// Styles for the component
const containerStyle = {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: "10px",
    padding: "20px",
    fontFamily: "Segoe UI, Roboto, Helvetica, sans-serif",
}

const buttonStyle = {
    padding: "10px 20px",
    backgroundColor: "#0078D7",
    color: "white",
    border: "none",
    borderRadius: "5px",
    cursor: "pointer",
    fontSize: "16px",
}

const responseStyle = {
    marginTop: "20px",
    padding: "15px",
    border: "1px solid #ddd",
    borderRadius: "5px",
    backgroundColor: "#f9f9f9",
    width: "100%",
    maxWidth: "400px",
}

const errorStyle = {
    color: "red",
    marginTop: "10px",
}

const mfaCodeStyle = {
    marginTop: "15px",
    padding: "10px",
    backgroundColor: "#f0f7ff",
    borderRadius: "4px",
    border: "1px solid #d0e5ff",
}

const mfaHeaderStyle = {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
}

const refreshButtonStyle = {
    padding: "5px 10px",
    backgroundColor: "#0078D7",
    color: "white",
    border: "none",
    borderRadius: "4px",
    cursor: "pointer",
    fontSize: "14px",
}

const codeDisplayStyle = {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    marginTop: "10px",
}

const codeStyle = {
    fontSize: "28px",
    fontWeight: "bold",
    letterSpacing: "4px",
    color: "#333",
    fontFamily: "monospace",
}

const progressBarContainer = {
    width: "100%",
    height: "4px",
    backgroundColor: "#e0e0e0",
    borderRadius: "2px",
    marginTop: "10px",
    marginBottom: "5px",
}

const progressBarStyle = {
    height: "100%",
    borderRadius: "2px",
    transition: "width 1s linear",
}

const timerStyle = {
    fontSize: "14px",
    color: "#666",
}

// Add property controls for Framer
addPropertyControls(AzureFunctionButton, {
    // Add any custom properties here if needed
})
