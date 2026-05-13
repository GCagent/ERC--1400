"""Voice Prosody Shaping API - FastAPI service for controlling speech synthesis prosody."""

from dataclasses import dataclass
from enum import Enum
from typing import Optional
import json

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


class EmotionalTone(str, Enum):
    NEUTRAL = "neutral"
    HAPPY = "happy"
    SAD = "sad"
    EXCITED = "excited"
    CALM = "calm"
    SERIOUS = "serious"


class ProsodyParams(BaseModel):
    pitch: float = Field(default=1.0, ge=0.5, le=2.0, description="Pitch multiplier (0.5-2.0)")
    rate: float = Field(default=1.0, ge=0.25, le=4.0, description="Speaking rate multiplier (0.25-4.0)")
    volume: float = Field(default=1.0, ge=0.0, le=1.0, description="Volume level (0.0-1.0)")
    emphasis: Optional[list[str]] = Field(default=None, description="Words to emphasize")
    pauses: Optional[dict[str, float]] = Field(default=None, description="Pause durations after words (in seconds)")
    tone: EmotionalTone = Field(default=EmotionalTone.NEUTRAL, description="Emotional tone preset")


class SynthesisRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000, description="Text to synthesize")
    prosody: ProsodyParams = Field(default_factory=ProsodyParams)
    output_format: str = Field(default="ssml", pattern="^(ssml|json|raw)$")


class SSMLBuilder:
    """Builds SSML markup from text and prosody parameters."""

    TONE_PRESETS = {
        EmotionalTone.NEUTRAL: {"pitch": "+0%", "rate": "medium"},
        EmotionalTone.HAPPY: {"pitch": "+10%", "rate": "fast"},
        EmotionalTone.SAD: {"pitch": "-10%", "rate": "slow"},
        EmotionalTone.EXCITED: {"pitch": "+20%", "rate": "fast"},
        EmotionalTone.CALM: {"pitch": "-5%", "rate": "slow"},
        EmotionalTone.SERIOUS: {"pitch": "-15%", "rate": "medium"},
    }

    @classmethod
    def build(cls, text: str, prosody: ProsodyParams) -> str:
        pitch_percent = int((prosody.pitch - 1.0) * 100)
        pitch_str = f"{pitch_percent:+d}%"

        rate_percent = int(prosody.rate * 100)
        rate_str = f"{rate_percent}%"

        volume_str = f"{int(prosody.volume * 100)}%"

        processed_text = cls._apply_emphasis(text, prosody.emphasis or [])
        processed_text = cls._apply_pauses(processed_text, prosody.pauses or {})

        ssml = f"""<speak>
  <prosody pitch="{pitch_str}" rate="{rate_str}" volume="{volume_str}">
    {processed_text}
  </prosody>
</speak>"""
        return ssml

    @classmethod
    def _apply_emphasis(cls, text: str, words: list[str]) -> str:
        for word in words:
            text = text.replace(word, f'<emphasis level="strong">{word}</emphasis>')
        return text

    @classmethod
    def _apply_pauses(cls, text: str, pauses: dict[str, float]) -> str:
        for word, duration in pauses.items():
            pause_ms = int(duration * 1000)
            text = text.replace(word, f'{word}<break time="{pause_ms}ms"/>')
        return text


@dataclass
class ProsodyAnalysis:
    pitch_contour: list[float]
    rate_variation: float
    pause_distribution: list[float]
    emphasis_points: list[int]


class ProsodyAnalyzer:
    """Analyzes text to suggest prosody parameters."""

    QUESTION_INDICATORS = ("?", "how", "what", "when", "where", "why", "who")
    EXCITEMENT_INDICATORS = ("!", "amazing", "incredible", "wow")

    @classmethod
    def suggest_prosody(cls, text: str) -> ProsodyParams:
        text_lower = text.lower()

        pitch = 1.0
        rate = 1.0
        tone = EmotionalTone.NEUTRAL

        if any(ind in text_lower for ind in cls.QUESTION_INDICATORS):
            pitch = 1.1
            tone = EmotionalTone.NEUTRAL

        if any(ind in text_lower for ind in cls.EXCITEMENT_INDICATORS):
            pitch = 1.15
            rate = 1.1
            tone = EmotionalTone.EXCITED

        if text_lower.startswith(("unfortunately", "sadly", "i regret")):
            pitch = 0.9
            rate = 0.9
            tone = EmotionalTone.SAD

        return ProsodyParams(pitch=pitch, rate=rate, tone=tone)


app = FastAPI(
    title="Voice Prosody Shaping API",
    description="API for controlling speech synthesis prosody parameters",
    version="1.0.0",
)


@app.post("/synthesize")
async def synthesize(request: SynthesisRequest) -> dict:
    """Generate prosody-shaped output from text."""
    if request.output_format == "ssml":
        output = SSMLBuilder.build(request.text, request.prosody)
    elif request.output_format == "json":
        output = {
            "text": request.text,
            "prosody": request.prosody.model_dump(),
            "ssml": SSMLBuilder.build(request.text, request.prosody),
        }
    else:
        output = request.text

    return {"status": "success", "output": output}


@app.post("/analyze")
async def analyze(text: str) -> dict:
    """Analyze text and suggest prosody parameters."""
    suggested = ProsodyAnalyzer.suggest_prosody(text)
    return {
        "text": text,
        "suggested_prosody": suggested.model_dump(),
        "ssml_preview": SSMLBuilder.build(text, suggested),
    }


@app.get("/presets")
async def get_presets() -> dict:
    """Get available emotional tone presets."""
    return {
        "presets": {tone.value: SSMLBuilder.TONE_PRESETS[tone] for tone in EmotionalTone}
    }


@app.get("/health")
async def health() -> dict:
    return {"status": "healthy"}
